#!/usr/bin/env python3
"""
AWS Demo - Lambda Function
Este script demuestra la ejecución de código Python en AWS Lambda (Serverless)
"""

import json
import os
import platform
import sys
from datetime import datetime
import boto3
from botocore.exceptions import ClientError
import base64
import traceback

# Clientes AWS
s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Handler principal de Lambda
    
    Args:
        event: Evento que trigger la función
        context: Objeto de contexto de Lambda con metadata de runtime
    
    Returns:
        dict: Respuesta con statusCode y body
    """
    
    try:
        # Determinar el tipo de evento
        event_source = detect_event_source(event)
        
        # Procesar según el tipo de evento
        if event_source == 'API_GATEWAY':
            return handle_api_gateway(event, context)
        elif event_source == 'S3':
            return handle_s3_event(event, context)
        elif event_source == 'SCHEDULED':
            return handle_scheduled_event(event, context)
        else:
            return handle_direct_invocation(event, context)
            
    except Exception as e:
        print(f"Error in lambda_handler: {str(e)}")
        print(traceback.format_exc())
        
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': str(e),
                'message': 'Internal server error'
            })
        }

def detect_event_source(event):
    """Detecta la fuente del evento"""
    if 'httpMethod' in event:
        return 'API_GATEWAY'
    elif 'Records' in event and event['Records']:
        if 's3' in event['Records'][0]:
            return 'S3'
    elif 'source' in event and event['source'] == 'aws.events':
        return 'SCHEDULED'
    else:
        return 'DIRECT'

def handle_api_gateway(event, context):
    """Maneja eventos de API Gateway"""
    
    # Obtener path y método
    path = event.get('path', '/')
    method = event.get('httpMethod', 'GET')
    
    # Obtener información de Lambda
    lambda_info = get_lambda_info(context)
    
    # Procesar según el path
    if path == '/' or path == '/info':
        response_data = {
            'timestamp': datetime.now().isoformat(),
            'message': '¡Hola desde AWS Lambda!',
            'service': 'AWS Lambda (API Gateway)',
            'lambda_info': lambda_info,
            'request_info': {
                'method': method,
                'path': path,
                'headers': event.get('headers', {}),
                'query_params': event.get('queryStringParameters', {})
            }
        }
        
        # Si es una petición web, devolver HTML
        if 'text/html' in event.get('headers', {}).get('Accept', ''):
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'text/html',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': generate_html_response(response_data)
            }
        else:
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps(response_data, indent=2)
            }
    
    elif path == '/process':
        # Procesar datos del body si existen
        body_data = {}
        if event.get('body'):
            try:
                body_data = json.loads(event['body'])
            except:
                body_data = {'raw': event['body']}
        
        result = process_data(body_data, context)
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(result, indent=2)
        }
    
    else:
        return {
            'statusCode': 404,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Path not found'})
        }

def handle_s3_event(event, context):
    """Maneja eventos de S3"""
    
    results = []
    
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        event_name = record['eventName']
        
        result = {
            'timestamp': datetime.now().isoformat(),
            'event_type': 'S3',
            'event_name': event_name,
            'bucket': bucket,
            'object_key': key,
            'processing_status': 'SUCCESS'
        }
        
        # Si es una creación de objeto, intentar leerlo
        if 'ObjectCreated' in event_name:
            try:
                response = s3_client.get_object(Bucket=bucket, Key=key)
                content_type = response['ContentType']
                size = response['ContentLength']
                
                result['object_info'] = {
                    'content_type': content_type,
                    'size_bytes': size,
                    'last_modified': response['LastModified'].isoformat()
                }
                
                # Log en CloudWatch
                print(f"Processed S3 object: s3://{bucket}/{key} ({size} bytes)")
                
            except Exception as e:
                result['processing_status'] = 'ERROR'
                result['error'] = str(e)
        
        results.append(result)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Processed {len(results)} S3 events',
            'results': results
        }, indent=2)
    }

def handle_scheduled_event(event, context):
    """Maneja eventos programados (CloudWatch Events)"""
    
    lambda_info = get_lambda_info(context)
    
    result = {
        'timestamp': datetime.now().isoformat(),
        'event_type': 'SCHEDULED',
        'service': 'AWS Lambda (CloudWatch Events)',
        'lambda_info': lambda_info,
        'schedule_info': {
            'time': event.get('time'),
            'id': event.get('id'),
            'resources': event.get('resources', [])
        },
        'message': 'Scheduled task executed successfully'
    }
    
    # Aquí podrías agregar lógica de negocio para tareas programadas
    # Por ejemplo: limpieza de datos, generación de reportes, etc.
    
    print(f"Scheduled execution at {result['timestamp']}")
    
    return {
        'statusCode': 200,
        'body': json.dumps(result, indent=2)
    }

def handle_direct_invocation(event, context):
    """Maneja invocaciones directas"""
    
    lambda_info = get_lambda_info(context)
    
    # Procesar datos de entrada
    processed_data = process_data(event, context)
    
    result = {
        'timestamp': datetime.now().isoformat(),
        'event_type': 'DIRECT_INVOCATION',
        'service': 'AWS Lambda',
        'lambda_info': lambda_info,
        'input_received': event,
        'processed_data': processed_data,
        'message': 'Direct invocation processed successfully'
    }
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json'
        },
        'body': json.dumps(result, indent=2)
    }

def process_data(data, context):
    """Procesa datos de entrada"""
    
    # Simulación de procesamiento
    result = {
        'processing_timestamp': datetime.now().isoformat(),
        'items_processed': len(data) if isinstance(data, (list, dict)) else 1,
        'execution_time_remaining': context.get_remaining_time_in_millis(),
        'memory_limit_mb': context.memory_limit_in_mb
    }
    
    # Análisis simple del contenido
    if isinstance(data, dict):
        result['keys_found'] = list(data.keys())
        result['data_type'] = 'dictionary'
    elif isinstance(data, list):
        result['list_length'] = len(data)
        result['data_type'] = 'list'
    else:
        result['data_type'] = type(data).__name__
    
    # Guardar métricas en CloudWatch (simulación)
    print(f"METRICS: Items={result['items_processed']}, Type={result['data_type']}")
    
    return result

def get_lambda_info(context):
    """Obtiene información sobre la función Lambda"""
    
    return {
        'function_name': context.function_name,
        'function_version': context.function_version,
        'invoked_function_arn': context.invoked_function_arn,
        'memory_limit_mb': context.memory_limit_in_mb,
        'aws_request_id': context.aws_request_id,
        'log_group_name': context.log_group_name,
        'log_stream_name': context.log_stream_name,
        'remaining_time_ms': context.get_remaining_time_in_millis(),
        'environment_variables': {
            k: v for k, v in os.environ.items() 
            if k.startswith(('AWS_', 'LAMBDA_')) or k in ['TZ', '_HANDLER']
        },
        'runtime': {
            'python_version': platform.python_version(),
            'platform': platform.platform()
        }
    }

def generate_html_response(data):
    """Genera una respuesta HTML"""
    
    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Lambda Function Demo - AWS Class</title>
        <style>
            body {{
                font-family: 'Amazon Ember', Arial, sans-serif;
                background: linear-gradient(135deg, #ff9900 0%, #ff6600 100%);
                color: white;
                padding: 40px;
                margin: 0;
            }}
            .container {{
                max-width: 900px;
                margin: 0 auto;
                background: white;
                color: #232f3e;
                padding: 30px;
                border-radius: 10px;
                box-shadow: 0 4px 6px rgba(0,0,0,0.3);
            }}
            h1 {{
                color: #ff9900;
                border-bottom: 3px solid #232f3e;
                padding-bottom: 10px;
            }}
            .metric {{
                background: #f2f3f3;
                padding: 15px;
                margin: 10px 0;
                border-left: 4px solid #ff9900;
            }}
            .lambda-info {{
                background: #fff3e0;
                padding: 15px;
                margin: 10px 0;
                border-left: 4px solid #ff9900;
            }}
            pre {{
                background: #282c34;
                color: #abb2bf;
                padding: 15px;
                border-radius: 5px;
                overflow-x: auto;
                font-size: 0.9em;
            }}
            .badge {{
                display: inline-block;
                padding: 3px 8px;
                background: #ff9900;
                color: white;
                border-radius: 3px;
                font-size: 0.8em;
                margin-left: 10px;
            }}
            .serverless {{
                color: #ff9900;
                font-weight: bold;
            }}
        </style>
    </head>
    <body>
        <div class="container">
            <h1>⚡ AWS Lambda Function <span class="badge">SERVERLESS</span></h1>
            <p>Generated at: {data['timestamp']}</p>
            
            <div class="lambda-info">
                <h3>Lambda Execution Context</h3>
                <p><strong>Function Name:</strong> {data['lambda_info']['function_name']}</p>
                <p><strong>Request ID:</strong> {data['lambda_info']['aws_request_id']}</p>
                <p><strong>Memory:</strong> {data['lambda_info']['memory_limit_mb']} MB</p>
                <p><strong>Time Remaining:</strong> {data['lambda_info']['remaining_time_ms']} ms</p>
            </div>
            
            <div class="metric">
                <h3>Runtime Information</h3>
                <p><strong>Python Version:</strong> {data['lambda_info']['runtime']['python_version']}</p>
                <p><strong>Platform:</strong> {data['lambda_info']['runtime']['platform']}</p>
            </div>
            
            <div class="metric">
                <h3>Message</h3>
                <p class="serverless">{data['message']}</p>
            </div>
            
            <h3>Full Response (JSON):</h3>
            <pre>{json.dumps(data, indent=2)}</pre>
        </div>
    </body>
    </html>
    """
    
    return html

# Para testing local
if __name__ == "__main__":
    # Evento de prueba
    test_event = {
        "test": "local",
        "data": "example"
    }
    
    # Contexto simulado
    class Context:
        function_name = "test-function"
        function_version = "$LATEST"
        invoked_function_arn = "arn:aws:lambda:us-east-1:123456789:function:test"
        memory_limit_in_mb = 128
        aws_request_id = "test-request-id"
        log_group_name = "/aws/lambda/test"
        log_stream_name = "test-stream"
        
        def get_remaining_time_in_millis(self):
            return 300000
    
    result = lambda_handler(test_event, Context())
    print(json.dumps(result, indent=2))