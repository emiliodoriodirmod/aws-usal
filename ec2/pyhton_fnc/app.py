#!/usr/bin/env python3
"""
AWS Demo - EC2 Application
Este script demuestra la ejecución de código Python en una instancia EC2
"""

import json
import platform
import socket
import os
from datetime import datetime
import boto3
from botocore.exceptions import NoCredentialsError

def get_instance_metadata():
    """Obtiene metadata de la instancia EC2 si está disponible"""
    try:
        # Intentar obtener el instance-id desde metadata service
        import urllib.request
        response = urllib.request.urlopen('http://169.254.169.254/latest/meta-data/instance-id', timeout=2)
        instance_id = response.read().decode('utf-8')
        
        response = urllib.request.urlopen('http://169.254.169.254/latest/meta-data/instance-type', timeout=2)
        instance_type = response.read().decode('utf-8')
        
        response = urllib.request.urlopen('http://169.254.169.254/latest/meta-data/placement/availability-zone', timeout=2)
        az = response.read().decode('utf-8')
        
        return {
            "instance_id": instance_id,
            "instance_type": instance_type,
            "availability_zone": az
        }
    except:
        return {
            "instance_id": "local-development",
            "instance_type": "local",
            "availability_zone": "local"
        }

def write_to_s3(data, bucket_name=None):
    """Escribe el resultado en S3 si está configurado"""
    if not bucket_name:
        return None
    
    try:
        s3 = boto3.client('s3')
        filename = f"ec2-output-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
        
        s3.put_object(
            Bucket=bucket_name,
            Key=f"ec2-outputs/{filename}",
            Body=json.dumps(data, indent=2),
            ContentType='application/json'
        )
        
        return f"s3://{bucket_name}/ec2-outputs/{filename}"
    except NoCredentialsError:
        return "S3 credentials not configured"
    except Exception as e:
        return f"S3 error: {str(e)}"

def create_html_output(data):
    """Crea una página HTML con los resultados"""
    html_content = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>EC2 Python Demo - AWS Class</title>
        <style>
            body {{
                font-family: 'Amazon Ember', Arial, sans-serif;
                background: linear-gradient(135deg, #232f3e 0%, #37475a 100%);
                color: white;
                padding: 40px;
                margin: 0;
            }}
            .container {{
                max-width: 800px;
                margin: 0 auto;
                background: white;
                color: #232f3e;
                padding: 30px;
                border-radius: 10px;
                box-shadow: 0 4px 6px rgba(0,0,0,0.3);
            }}
            h1 {{
                color: #ff9900;
                border-bottom: 3px solid #ff9900;
                padding-bottom: 10px;
            }}
            .metric {{
                background: #f2f3f3;
                padding: 15px;
                margin: 10px 0;
                border-left: 4px solid #ff9900;
            }}
            .timestamp {{
                color: #666;
                font-size: 0.9em;
            }}
            pre {{
                background: #282c34;
                color: #abb2bf;
                padding: 15px;
                border-radius: 5px;
                overflow-x: auto;
            }}
            .success {{
                color: #48bb78;
                font-weight: bold;
            }}
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🖥️ EC2 Instance - Python Demo</h1>
            <p class="timestamp">Generated at: {data['timestamp']}</p>
            
            <div class="metric">
                <h3>Instance Information</h3>
                <p><strong>Instance ID:</strong> {data['metadata']['instance_id']}</p>
                <p><strong>Instance Type:</strong> {data['metadata']['instance_type']}</p>
                <p><strong>Availability Zone:</strong> {data['metadata']['availability_zone']}</p>
            </div>
            
            <div class="metric">
                <h3>System Information</h3>
                <p><strong>Hostname:</strong> {data['system_info']['hostname']}</p>
                <p><strong>Platform:</strong> {data['system_info']['platform']}</p>
                <p><strong>Python Version:</strong> {data['system_info']['python_version']}</p>
                <p><strong>CPU Count:</strong> {data['system_info']['cpu_count']}</p>
            </div>
            
            <div class="metric">
                <h3>Status</h3>
                <p class="success">✅ {data['status']}</p>
                <p>{data['message']}</p>
            </div>
            
            <h3>Raw JSON Output:</h3>
            <pre>{json.dumps(data, indent=2)}</pre>
        </div>
    </body>
    </html>
    """
    
    # Guardar el archivo HTML
    with open('/var/www/html/index.html', 'w') as f:
        f.write(html_content)
    
    return html_content

def main():
    """Función principal"""
    
    # Obtener información del sistema
    metadata = get_instance_metadata()
    
    system_info = {
        "hostname": socket.gethostname(),
        "platform": platform.platform(),
        "python_version": platform.python_version(),
        "processor": platform.processor() or "Unknown",
        "cpu_count": os.cpu_count(),
        "current_directory": os.getcwd()
    }
    
    # Crear el objeto de datos
    data = {
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "service": "Amazon EC2",
        "metadata": metadata,
        "system_info": system_info,
        "status": "SUCCESS",
        "message": "¡Hola desde EC2! Esta aplicación Python está ejecutándose en una instancia de Amazon EC2.",
        "demo_features": [
            "Obteniendo metadata de la instancia",
            "Información del sistema operativo",
            "Publicando resultado en formato JSON",
            "Generando página HTML (si hay servidor web)",
            "Opcionalmente guardando en S3"
        ]
    }
    
    # Imprimir en consola
    print("\n" + "="*50)
    print("AWS EC2 PYTHON DEMO")
    print("="*50)
    print(json.dumps(data, indent=2))
    
    # Guardar en archivo local
    output_file = f"ec2-output-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
    with open(output_file, 'w') as f:
        json.dump(data, f, indent=2)
    print(f"\n✅ Output saved to: {output_file}")
    
    # Intentar crear HTML (si tenemos permisos)
    try:
        create_html_output(data)
        print("✅ HTML page created at /var/www/html/index.html")
    except Exception as e:
        print(f"ℹ️ Could not create HTML: {e}")
    
    # Intentar escribir en S3 (si está configurado)
    bucket_name = os.environ.get('S3_BUCKET_NAME')
    if bucket_name:
        s3_location = write_to_s3(data, bucket_name)
        print(f"✅ Uploaded to S3: {s3_location}")
    
    return data

if __name__ == "__main__":
    main()