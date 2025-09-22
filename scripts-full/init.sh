#!/bin/bash

# Script de deployment para los 3 escenarios de cómputo AWS
# Autor: AWS Demo Class
# Fecha: 2024

set -e  # Exit on error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Variables
REGION=${AWS_REGION:-"sa-east-1"}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
KEY_NAME="aws-demo-key-${TIMESTAMP}"
SECURITY_GROUP_NAME="aws-demo-sg-${TIMESTAMP}"
BUCKET_NAME="aws-demo-bucket-${ACCOUNT_ID}-${TIMESTAMP}"

echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}     AWS Compute Services Demo Deployment Script${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "Region: ${YELLOW}${REGION}${NC}"
echo -e "Account ID: ${YELLOW}${ACCOUNT_ID}${NC}"
echo -e "Timestamp: ${YELLOW}${TIMESTAMP}${NC}\n"

# =================================================================
# PREPARACIÓN INICIAL
# =================================================================

echo -e "${YELLOW}[1/4] PREPARACIÓN INICIAL${NC}"

# Crear key pair
echo "→ Creando key pair..."
aws ec2 create-key-pair \
    --key-name ${KEY_NAME} \
    --query 'KeyMaterial' \
    --output text > ${KEY_NAME}.pem
chmod 400 ${KEY_NAME}.pem
echo -e "${GREEN}✓ Key pair creado: ${KEY_NAME}${NC}"

# Crear Security Group
echo "→ Creando Security Group..."
SG_ID=$(aws ec2 create-security-group \
    --group-name ${SECURITY_GROUP_NAME} \
    --description "Security group for AWS demo class" \
    --query 'GroupId' \
    --output text)

# Agregar reglas al Security Group
aws ec2 authorize-security-group-ingress \
    --group-id ${SG_ID} \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 >/dev/null

aws ec2 authorize-security-group-ingress \
    --group-id ${SG_ID} \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 >/dev/null

aws ec2 authorize-security-group-ingress \
    --group-id ${SG_ID} \
    --protocol tcp \
    --port 8080 \
    --cidr 0.0.0.0/0 >/dev/null

echo -e "${GREEN}✓ Security Group creado: ${SG_ID}${NC}"

# Crear bucket S3
echo "→ Creando bucket S3..."
aws s3 mb s3://${BUCKET_NAME} --region ${REGION} >/dev/null
echo -e "${GREEN}✓ Bucket S3 creado: ${BUCKET_NAME}${NC}\n"

# =================================================================
# EC2 DEPLOYMENT
# =================================================================

echo -e "${YELLOW}[2/4] DESPLEGANDO EC2${NC}"

# Obtener AMI ID más reciente de Amazon Linux 2
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-*" \
              "Name=architecture,Values=x86_64" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text)

echo "→ Usando AMI: ${AMI_ID}"

# Crear archivo user data
cat > user-data-ec2.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y python3 python3-pip httpd
systemctl start httpd
systemctl enable httpd
pip3 install boto3

cat > /opt/app.py << 'PYEOF'
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
PYEOF

python3 /opt/app.py > /var/log/app.log 2>&1
echo "*/5 * * * * python3 /opt/app.py >> /var/log/app.log 2>&1" | crontab -
EOF

# Lanzar instancia EC2
echo "→ Lanzando instancia EC2..."
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id ${AMI_ID} \
    --instance-type t2.micro \
    --key-name ${KEY_NAME} \
    --security-group-ids ${SG_ID} \
    --user-data file://user-data-ec2.sh \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=EC2-Demo-${TIMESTAMP}}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

echo -e "${GREEN}✓ Instancia EC2 lanzada: ${INSTANCE_ID}${NC}"

# Esperar a que la instancia esté running
echo "→ Esperando que la instancia esté lista..."
aws ec2 wait instance-running --instance-ids ${INSTANCE_ID}

# Obtener IP pública
EC2_PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids ${INSTANCE_ID} \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

echo -e "${GREEN}✓ EC2 disponible en: http://${EC2_PUBLIC_IP}${NC}\n"

# =================================================================
# ECS/FARGATE DEPLOYMENT
# =================================================================

echo -e "${YELLOW}[3/4] DESPLEGANDO ECS/FARGATE${NC}"

# Crear repositorio ECR
echo "→ Creando repositorio ECR..."
REPO_URI=$(aws ecr create-repository \
    --repository-name demo-ecs-${TIMESTAMP} \
    --query 'repository.repositoryUri' \
    --output text 2>/dev/null || \
    aws ecr describe-repositories \
    --repository-names demo-ecs-${TIMESTAMP} \
    --query 'repositories[0].repositoryUri' \
    --output text)

echo -e "${GREEN}✓ Repositorio ECR: ${REPO_URI}${NC}"

# Login a ECR
echo "→ Login a ECR..."
aws ecr get-login-password --region ${REGION} | \
    docker login --username AWS --password-stdin ${REPO_URI} >/dev/null 2>&1

# Build y push de imagen Docker
echo "→ Construyendo imagen Docker..."
docker build -t demo-ecs:latest . >/dev/null 2>&1
docker tag demo-ecs:latest ${REPO_URI}:latest
docker push ${REPO_URI}:latest >/dev/null 2>&1
echo -e "${GREEN}✓ Imagen Docker pushed${NC}"

# Crear cluster ECS
echo "→ Creando cluster ECS..."
aws ecs create-cluster --cluster-name demo-cluster-${TIMESTAMP} >/dev/null

# Crear task definition
cat > task-definition.json << EOF
{
  "family": "demo-task-${TIMESTAMP}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "containerDefinitions": [
    {
      "name": "demo-container",
      "image": "${REPO_URI}:latest",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8080,
          "protocol": "tcp"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/demo-${TIMESTAMP}",
          "awslogs-region": "${REGION}",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
EOF

# Crear log group
aws logs create-log-group --log-group-name /ecs/demo-${TIMESTAMP} 2>/dev/null || true

# Registrar task definition
echo "→ Registrando task definition..."
aws ecs register-task-definition --cli-input-json file://task-definition.json >/dev/null

# Obtener subnets de la VPC default
DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text)

SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${DEFAULT_VPC_ID}" \
    --query 'Subnets[0].SubnetId' \
    --output text)

# Ejecutar tarea en Fargate
echo "→ Ejecutando tarea en Fargate..."
TASK_ARN=$(aws ecs run-task \
    --cluster demo-cluster-${TIMESTAMP} \
    --task-definition demo-task-${TIMESTAMP} \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_ID}],securityGroups=[${SG_ID}],assignPublicIp=ENABLED}" \
    --query 'tasks[0].taskArn' \
    --output text)

echo -e "${GREEN}✓ Tarea ECS ejecutándose${NC}\n"

# =================================================================
# LAMBDA DEPLOYMENT
# =================================================================

echo -e "${YELLOW}[4/4] DESPLEGANDO LAMBDA${NC}"

# Crear rol IAM para Lambda
echo "→ Creando rol IAM para Lambda..."
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

ROLE_ARN=$(aws iam create-role \
    --role-name lambda-demo-role-${TIMESTAMP} \
    --assume-role-policy-document file://trust-policy.json \
    --query 'Role.Arn' \
    --output text 2>/dev/null || \
    aws iam get-role \
    --role-name lambda-demo-role-${TIMESTAMP} \
    --query 'Role.Arn' \
    --output text)

# Adjuntar políticas al rol
aws iam attach-role-policy \
    --role-name lambda-demo-role-${TIMESTAMP} \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

sleep 10  # Esperar propagación del rol

# Crear archivo ZIP con la función
echo "→ Preparando función Lambda..."
zip -q function.zip lambda_function.py

# Crear función Lambda
echo "→ Creando función Lambda..."
LAMBDA_ARN=$(aws lambda create-function \
    --function-name demo-lambda-${TIMESTAMP} \
    --runtime python3.9 \
    --role ${ROLE_ARN} \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://function.zip \
    --timeout 30 \
    --memory-size 256 \
    --environment "Variables={S3_BUCKET=${BUCKET_NAME}}" \
    --query 'FunctionArn' \
    --output text)

echo -e "${GREEN}✓ Función Lambda creada${NC}"

# Crear API Gateway
echo "→ Creando API Gateway..."
API_ID=$(aws apigatewayv2 create-api \
    --name demo-api-${TIMESTAMP} \
    --protocol-type HTTP \
    --target ${LAMBDA_ARN} \
    --query 'ApiId' \
    --output text)

# Dar permisos a API Gateway para invocar Lambda
aws lambda add-permission \
    --function-name demo-lambda-${TIMESTAMP} \
    --statement-id api-gateway \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/*" >/dev/null 2>&1

API_ENDPOINT=$(aws apigatewayv2 get-api \
    --api-id ${API_ID} \
    --query 'ApiEndpoint' \
    --output text)

echo -e "${GREEN}✓ API Gateway disponible en: ${API_ENDPOINT}${NC}\n"

# =================================================================
# RESUMEN FINAL
# =================================================================

echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}              DEPLOYMENT COMPLETADO${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}RECURSOS CREADOS:${NC}"
echo "├── EC2:"
echo "│   ├── Instance ID: ${INSTANCE_ID}"
echo "│   ├── Public IP: ${EC2_PUBLIC_IP}"
echo "│   └── URL: http://${EC2_PUBLIC_IP}"
echo "├── ECS/Fargate:"
echo "│   ├── Cluster: demo-cluster-${TIMESTAMP}"
echo "│   ├── Task: demo-task-${TIMESTAMP}"
echo "│   └── Task ARN: ${TASK_ARN}"
echo "├── Lambda:"
echo "│   ├── Function: demo-lambda-${TIMESTAMP}"
echo "│   └── API URL: ${API_ENDPOINT}"
echo "└── Recursos compartidos:"
echo "    ├── S3 Bucket: ${BUCKET_NAME}"
echo "    ├── Security Group: ${SG_ID}"
echo "    └── Key Pair: ${KEY_NAME}"
echo ""
echo -e "${YELLOW}COMANDOS ÚTILES:${NC}"
echo "# SSH a EC2:"
echo "ssh -i ${KEY_NAME}.pem ec2-user@${EC2_PUBLIC_IP}"
echo ""
echo "# Ver logs de ECS:"
echo "aws logs tail /ecs/demo-${TIMESTAMP} --follow"
echo ""
echo "# Invocar Lambda:"
echo "curl ${API_ENDPOINT}"
echo ""
echo "# Test Lambda con datos:"
echo "aws lambda invoke --function-name demo-lambda-${TIMESTAMP} --payload '{\"test\":\"data\"}' response.json"
echo ""
echo -e "${RED}LIMPIEZA:${NC}"
echo "Para eliminar todos los recursos creados, ejecuta:"
echo "./cleanup.sh ${TIMESTAMP}"
echo ""

# Crear script de limpieza
cat > cleanup-${TIMESTAMP}.sh << EOF
#!/bin/bash
# Script de limpieza para recursos creados el ${TIMESTAMP}

echo "Eliminando recursos AWS..."

# Terminar instancia EC2
aws ec2 terminate-instances --instance-ids ${INSTANCE_ID} 2>/dev/null

# Detener tareas ECS
aws ecs stop-task --cluster demo-cluster-${TIMESTAMP} --task ${TASK_ARN} 2>/dev/null

# Eliminar cluster ECS
aws ecs delete-cluster --cluster demo-cluster-${TIMESTAMP} 2>/dev/null

# Eliminar función Lambda
aws lambda delete-function --function-name demo-lambda-${TIMESTAMP} 2>/dev/null

# Eliminar API Gateway
aws apigatewayv2 delete-api --api-id ${API_ID} 2>/dev/null

# Eliminar rol IAM
aws iam detach-role-policy --role-name lambda-demo-role-${TIMESTAMP} --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null
aws iam delete-role --role-name lambda-demo-role-${TIMESTAMP} 2>/dev/null

# Eliminar repositorio ECR
aws ecr delete-repository --repository-name demo-ecs-${TIMESTAMP} --force 2>/dev/null

# Eliminar log groups
aws logs delete-log-group --log-group-name /ecs/demo-${TIMESTAMP} 2>/dev/null
aws logs delete-log-group --log-group-name /aws/lambda/demo-lambda-${TIMESTAMP} 2>/dev/null

# Esperar terminación de EC2
aws ec2 wait instance-terminated --instance-ids ${INSTANCE_ID} 2>/dev/null

# Eliminar Security Group
aws ec2 delete-security-group --group-id ${SG_ID} 2>/dev/null

# Eliminar Key Pair
aws ec2 delete-key-pair --key-name ${KEY_NAME} 2>/dev/null
rm -f ${KEY_NAME}.pem

# Vaciar y eliminar bucket S3
aws s3 rm s3://${BUCKET_NAME} --recursive 2>/dev/null
aws s3 rb s3://${BUCKET_NAME} 2>/dev/null

echo "Limpieza completada."
EOF

chmod +x cleanup-${TIMESTAMP}.sh

echo -e "${GREEN}Script de limpieza creado: cleanup-${TIMESTAMP}.sh${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
