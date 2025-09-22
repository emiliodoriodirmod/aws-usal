#!/bin/bash

# Script de deployment para los 3 escenarios de cómputo AWS - VERSIÓN CORREGIDA
# Autor: AWS Demo Class
# Fecha: 2024

set -e  # Exit on error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Variables
REGION=${AWS_REGION:-"us-east-1"}
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

# Crear bucket S3 (con nombre único para evitar conflictos)
echo "→ Creando bucket S3..."
BUCKET_NAME="aws-demo-${ACCOUNT_ID}-${TIMESTAMP}"
if [ "${REGION}" = "us-east-1" ]; then
    aws s3 mb s3://${BUCKET_NAME} >/dev/null
else
    aws s3 mb s3://${BUCKET_NAME} --region ${REGION} >/dev/null
fi
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
              "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text)

echo "→ Usando AMI: ${AMI_ID}"

# Crear archivo user data (con el código Python embebido)
cat > user-data-ec2.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y python3 python3-pip httpd
systemctl start httpd
systemctl enable httpd
pip3 install boto3

mkdir -p /opt/aws-demo

cat > /opt/aws-demo/app.py << 'PYEOF'
#!/usr/bin/env python3
import json
import platform
import socket
import os
from datetime import datetime

def get_instance_metadata():
    try:
        import urllib.request
        base_url = 'http://169.254.169.254/latest/meta-data/'
        
        instance_id = urllib.request.urlopen(base_url + 'instance-id', timeout=2).read().decode('utf-8')
        instance_type = urllib.request.urlopen(base_url + 'instance-type', timeout=2).read().decode('utf-8')
        az = urllib.request.urlopen(base_url + 'placement/availability-zone', timeout=2).read().decode('utf-8')
        
        return {
            "instance_id": instance_id,
            "instance_type": instance_type,
            "availability_zone": az
        }
    except:
        return {
            "instance_id": "not-in-ec2",
            "instance_type": "unknown",
            "availability_zone": "unknown"
        }

def main():
    metadata = get_instance_metadata()
    
    data = {
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "service": "Amazon EC2",
        "metadata": metadata,
        "hostname": socket.gethostname(),
        "platform": platform.platform(),
        "python_version": platform.python_version(),
        "message": "Hello from EC2!"
    }
    
    # Crear página HTML
    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>EC2 Demo</title>
        <style>
            body {{ font-family: Arial; background: #232f3e; color: white; padding: 40px; }}
            .container {{ max-width: 800px; margin: 0 auto; background: white; color: #232f3e; padding: 30px; border-radius: 10px; }}
            h1 {{ color: #ff9900; }}
        </style>
    </head>
    <body>
        <div class="container">
            <h1>EC2 Instance Demo</h1>
            <p>Instance ID: {metadata['instance_id']}</p>
            <p>Instance Type: {metadata['instance_type']}</p>
            <p>Availability Zone: {metadata['availability_zone']}</p>
            <p>Generated at: {data['timestamp']}</p>
            <pre>{json.dumps(data, indent=2)}</pre>
        </div>
    </body>
    </html>
    """
    
    with open('/var/www/html/index.html', 'w') as f:
        f.write(html)
    
    print(json.dumps(data, indent=2))

if __name__ == "__main__":
    main()
PYEOF

chmod +x /opt/aws-demo/app.py
python3 /opt/aws-demo/app.py > /var/log/app.log 2>&1
echo "*/5 * * * * python3 /opt/aws-demo/app.py > /var/www/html/data.json 2>&1" | crontab -
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
# ECS/FARGATE DEPLOYMENT - VERSIÓN CORREGIDA
# =================================================================

echo -e "${YELLOW}[3/4] DESPLEGANDO ECS/FARGATE${NC}"

# Nombre del repositorio ECR
ECR_REPO_NAME="demo-ecs-${TIMESTAMP}"

# Crear repositorio ECR
echo "→ Creando repositorio ECR..."
aws ecr create-repository \
    --repository-name ${ECR_REPO_NAME} \
    --region ${REGION} >/dev/null 2>&1 || true

# Obtener el URI del repositorio (formato correcto)
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO_NAME}"
echo "→ ECR URI: ${ECR_URI}"

# Login a ECR - MÉTODO CORREGIDO
echo "→ Login a ECR..."
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# Crear archivos para Docker
echo "→ Creando archivos Docker..."

# Crear Dockerfile
cat > Dockerfile << 'DOCKERFILE'
FROM python:3.9-slim
WORKDIR /app
RUN pip install boto3
COPY app.py .
EXPOSE 8080
CMD ["python", "app.py"]
DOCKERFILE

# Crear app.py para ECS
cat > app.py << 'PYFILE'
#!/usr/bin/env python3
import json
import platform
import socket
import os
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = 8080

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        data = {
            "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "service": "Amazon ECS/Fargate",
            "container_id": socket.gethostname(),
            "platform": platform.platform(),
            "python_version": platform.python_version(),
            "port": PORT,
            "message": "Hello from ECS Container!"
        }
        
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'healthy')
        elif self.path == '/json':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(data, indent=2).encode())
        else:
            html = f"""
            <!DOCTYPE html>
            <html>
            <head>
                <title>ECS Demo</title>
                <style>
                    body {{ font-family: Arial; background: #146eb4; color: white; padding: 40px; }}
                    .container {{ max-width: 800px; margin: 0 auto; background: white; color: #232f3e; padding: 30px; border-radius: 10px; }}
                    h1 {{ color: #146eb4; }}
                </style>
            </head>
            <body>
                <div class="container">
                    <h1>ECS Container Demo</h1>
                    <p>Container ID: {data['container_id']}</p>
                    <p>Port: {data['port']}</p>
                    <p>Generated at: {data['timestamp']}</p>
                    <pre>{json.dumps(data, indent=2)}</pre>
                </div>
            </body>
            </html>
            """
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(html.encode())
    
    def log_message(self, format, *args):
        if '/health' not in args[0]:
            super().log_message(format, *args)

print(f"Starting server on port {PORT}")
httpd = HTTPServer(('', PORT), Handler)
httpd.serve_forever()
PYFILE

# Build y push de imagen Docker
echo "→ Construyendo imagen Docker..."
docker build -t ${ECR_REPO_NAME}:latest . 

echo "→ Etiquetando imagen..."
docker tag ${ECR_REPO_NAME}:latest ${ECR_URI}:latest

echo "→ Pushing imagen a ECR..."
docker push ${ECR_URI}:latest

echo -e "${GREEN}✓ Imagen Docker pushed a ECR${NC}"

# Crear rol de ejecución para ECS
echo "→ Creando rol de ejecución ECS..."
cat > ecs-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

ECS_ROLE_NAME="ecsTaskExecutionRole-${TIMESTAMP}"
aws iam create-role \
    --role-name ${ECS_ROLE_NAME} \
    --assume-role-policy-document file://ecs-trust-policy.json >/dev/null 2>&1 || true

aws iam attach-role-policy \
    --role-name ${ECS_ROLE_NAME} \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

ECS_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ECS_ROLE_NAME}"

# Crear cluster ECS
echo "→ Creando cluster ECS..."
aws ecs create-cluster --cluster-name demo-cluster-${TIMESTAMP} >/dev/null

# Crear log group
aws logs create-log-group --log-group-name /ecs/demo-${TIMESTAMP} 2>/dev/null || true

# Crear task definition
cat > task-definition.json << EOF
{
  "family": "demo-task-${TIMESTAMP}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "${ECS_ROLE_ARN}",
  "containerDefinitions": [
    {
      "name": "demo-container",
      "image": "${ECR_URI}:latest",
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

echo -e "${GREEN}✓ Tarea ECS ejecutándose${NC}"

# Esperar un poco y obtener la IP pública de la tarea
sleep 10
echo "→ Obteniendo IP de la tarea ECS..."
TASK_DETAILS=$(aws ecs describe-tasks \
    --cluster demo-cluster-${TIMESTAMP} \
    --tasks ${TASK_ARN} \
    --query 'tasks[0].attachments[0].details' \
    --output json)

ENI_ID=$(echo $TASK_DETAILS | python3 -c "import sys, json; details=json.load(sys.stdin); print([d['value'] for d in details if d['name']=='networkInterfaceId'][0])" 2>/dev/null || echo "")

if [ ! -z "$ENI_ID" ]; then
    ECS_PUBLIC_IP=$(aws ec2 describe-network-interfaces \
        --network-interface-ids ${ENI_ID} \
        --query 'NetworkInterfaces[0].Association.PublicIp' \
        --output text 2>/dev/null || echo "pending")
    
    if [ "$ECS_PUBLIC_IP" != "pending" ] && [ ! -z "$ECS_PUBLIC_IP" ]; then
        echo -e "${GREEN}✓ ECS disponible en: http://${ECS_PUBLIC_IP}:8080${NC}"
    fi
fi

echo ""

# =================================================================
# LAMBDA DEPLOYMENT
# =================================================================

echo -e "${YELLOW}[4/4] DESPLEGANDO LAMBDA${NC}"

# Crear archivo Lambda
cat > lambda_function.py << 'LAMBDAPY'
import json
import platform
from datetime import datetime

def lambda_handler(event, context):
    data = {
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "service": "AWS Lambda",
        "function_name": context.function_name,
        "request_id": context.aws_request_id,
        "memory_limit": context.memory_limit_in_mb,
        "remaining_time": context.get_remaining_time_in_millis(),
        "python_version": platform.python_version(),
        "message": "Hello from Lambda!"
    }
    
    # Generar HTML si viene de un navegador
    if event.get('headers', {}).get('accept', '').find('text/html') != -1:
        html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>Lambda Demo</title>
            <style>
                body {{ font-family: Arial; background: #ff9900; color: white; padding: 40px; }}
                .container {{ max-width: 800px; margin: 0 auto; background: white; color: #232f3e; padding: 30px; border-radius: 10px; }}
                h1 {{ color: #ff9900; }}
            </style>
        </head>
        <body>
            <div class="container">
                <h1>Lambda Function Demo</h1>
                <p>Function: {data['function_name']}</p>
                <p>Request ID: {data['request_id']}</p>
                <p>Memory: {data['memory_limit']} MB</p>
                <p>Generated at: {data['timestamp']}</p>
                <pre>{json.dumps(data, indent=2)}</pre>
            </div>
        </body>
        </html>
        """
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'text/html'},
            'body': html
        }
    
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps(data, indent=2)
    }
LAMBDAPY

# Crear rol IAM para Lambda
echo "→ Creando rol IAM para Lambda..."
cat > lambda-trust-policy.json << EOF
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

LAMBDA_ROLE_NAME="lambda-demo-role-${TIMESTAMP}"
aws iam create-role \
    --role-name ${LAMBDA_ROLE_NAME} \
    --assume-role-policy-document file://lambda-trust-policy.json >/dev/null 2>&1 || true

aws iam attach-role-policy \
    --role-name ${LAMBDA_ROLE_NAME} \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

LAMBDA_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"

sleep 10  # Esperar propagación del rol

# Crear archivo ZIP con la función
echo "→ Preparando función Lambda..."
zip -q function.zip lambda_function.py

# Crear función Lambda
echo "→ Creando función Lambda..."
LAMBDA_ARN=$(aws lambda create-function \
    --function-name demo-lambda-${TIMESTAMP} \
    --runtime python3.9 \
    --role ${LAMBDA_ROLE_ARN} \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://function.zip \
    --timeout 30 \
    --memory-size 256 \
    --environment "Variables={S3_BUCKET=${BUCKET_NAME}}" \
    --query 'FunctionArn' \
    --output text)

echo -e "${GREEN}✓ Función Lambda creada${NC}"

# Crear Function URL (más simple que API Gateway)
echo "→ Creando Function URL..."
FUNCTION_URL=$(aws lambda create-function-url-config \
    --function-name demo-lambda-${TIMESTAMP} \
    --auth-type NONE \
    --query 'FunctionUrl' \
    --output text)

# Agregar permisos para Function URL
aws lambda add-permission \
    --function-name demo-lambda-${TIMESTAMP} \
    --statement-id FunctionURLAllowPublicAccess \
    --action lambda:InvokeFunctionUrl \
    --principal '*' \
    --function-url-auth-type NONE >/dev/null 2>&1

echo -e "${GREEN}✓ Lambda disponible en: ${FUNCTION_URL}${NC}\n"

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
if [ ! -z "$ECS_PUBLIC_IP" ] && [ "$ECS_PUBLIC_IP" != "pending" ]; then
echo "│   └── URL: http://${ECS_PUBLIC_IP}:8080"
fi
echo "├── Lambda:"
echo "│   ├── Function: demo-lambda-${TIMESTAMP}"
echo "│   └── URL: ${FUNCTION_URL}"
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
echo "# Test Lambda:"
echo "curl ${FUNCTION_URL}"
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"

# Limpiar archivos temporales
rm -f user-data-ec2.sh task-definition.json ecs-trust-policy.json lambda-trust-policy.json function.zip Dockerfile app.py lambda_function.py

echo ""
echo "Deployment completado exitosamente!"