#!/bin/bash

# Script de limpieza para recursos AWS Demo
# Elimina TODOS los recursos creados durante la demo
# Autor: AWS Demo Class
# Fecha: 2024

set +e  # Continuar aunque haya errores (queremos limpiar todo lo posible)

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
REGION=${AWS_REGION:-"us-east-1"}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)

# Verificar si se pasó un timestamp específico
TIMESTAMP_FILTER=$1

echo -e "${RED}═══════════════════════════════════════════════════════${NC}"
echo -e "${RED}        AWS Demo - Script de Limpieza${NC}"
echo -e "${RED}═══════════════════════════════════════════════════════${NC}"
echo -e "Region: ${YELLOW}${REGION}${NC}"
echo -e "Account ID: ${YELLOW}${ACCOUNT_ID}${NC}"

if [ ! -z "$TIMESTAMP_FILTER" ]; then
    echo -e "Filtro Timestamp: ${YELLOW}${TIMESTAMP_FILTER}${NC}"
    echo -e "${YELLOW}⚠️  Eliminando solo recursos con timestamp: ${TIMESTAMP_FILTER}${NC}"
else
    echo -e "${RED}⚠️  ADVERTENCIA: Eliminando TODOS los recursos de demo${NC}"
fi

echo ""
read -p "¿Estás seguro de que quieres eliminar estos recursos? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo "Operación cancelada."
    exit 1
fi

echo ""
echo -e "${YELLOW}Iniciando limpieza...${NC}"
echo ""

# Función para imprimir estado
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
    fi
}

# Contador de recursos eliminados
TOTAL_DELETED=0
TOTAL_FAILED=0

# =================================================================
# LIMPIEZA EC2
# =================================================================

echo -e "${BLUE}[1/8] Limpiando recursos EC2...${NC}"

# Buscar y terminar instancias EC2
echo "→ Buscando instancias EC2..."
if [ ! -z "$TIMESTAMP_FILTER" ]; then
    INSTANCE_IDS=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=EC2-Demo-${TIMESTAMP_FILTER}" \
                  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text)
else
    INSTANCE_IDS=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=EC2-Demo-*" \
                  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text)
fi

if [ ! -z "$INSTANCE_IDS" ]; then
    for INSTANCE_ID in $INSTANCE_IDS; do
        echo "  Terminando instancia: $INSTANCE_ID"
        aws ec2 terminate-instances --instance-ids $INSTANCE_ID >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            print_status 0 "Instancia $INSTANCE_ID terminada"
            ((TOTAL_DELETED++))
        else
            print_status 1 "Error terminando $INSTANCE_ID"
            ((TOTAL_FAILED++))
        fi
    done
    
    # Esperar a que las instancias terminen
    echo "  Esperando terminación de instancias..."
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS 2>/dev/null
else
    echo "  No se encontraron instancias EC2"
fi

# =================================================================
# LIMPIEZA ECS
# =================================================================

echo -e "\n${BLUE}[2/8] Limpiando recursos ECS...${NC}"

# Buscar y detener tareas ECS
echo "→ Buscando clusters ECS..."
if [ ! -z "$TIMESTAMP_FILTER" ]; then
    CLUSTER_ARNS=$(aws ecs list-clusters --query "clusterArns[?contains(@, 'demo-cluster-${TIMESTAMP_FILTER}')]" --output text)
else
    CLUSTER_ARNS=$(aws ecs list-clusters --query "clusterArns[?contains(@, 'demo-cluster-')]" --output text)
fi

if [ ! -z "$CLUSTER_ARNS" ]; then
    for CLUSTER_ARN in $CLUSTER_ARNS; do
        CLUSTER_NAME=$(echo $CLUSTER_ARN | rev | cut -d'/' -f1 | rev)
        echo "  Procesando cluster: $CLUSTER_NAME"
        
        # Detener tareas
        TASK_ARNS=$(aws ecs list-tasks --cluster $CLUSTER_NAME --query 'taskArns' --output text)
        if [ ! -z "$TASK_ARNS" ]; then
            for TASK_ARN in $TASK_ARNS; do
                echo "    Deteniendo tarea..."
                aws ecs stop-task --cluster $CLUSTER_NAME --task $TASK_ARN >/dev/null 2>&1
                print_status $? "Tarea detenida"
                ((TOTAL_DELETED++))
            done
        fi
        
        # Eliminar servicios
        SERVICE_ARNS=$(aws ecs list-services --cluster $CLUSTER_NAME --query 'serviceArns' --output text)
        if [ ! -z "$SERVICE_ARNS" ]; then
            for SERVICE_ARN in $SERVICE_ARNS; do
                SERVICE_NAME=$(echo $SERVICE_ARN | rev | cut -d'/' -f1 | rev)
                echo "    Eliminando servicio: $SERVICE_NAME"
                aws ecs update-service --cluster $CLUSTER_NAME --service $SERVICE_NAME --desired-count 0 >/dev/null 2>&1
                aws ecs delete-service --cluster $CLUSTER_NAME --service $SERVICE_NAME >/dev/null 2>&1
                print_status $? "Servicio eliminado"
                ((TOTAL_DELETED++))
            done
        fi
        
        # Eliminar cluster
        echo "  Eliminando cluster: $CLUSTER_NAME"
        aws ecs delete-cluster --cluster $CLUSTER_NAME >/dev/null 2>&1
        print_status $? "Cluster eliminado"
        ((TOTAL_DELETED++))
    done
else
    echo "  No se encontraron clusters ECS"
fi

# Eliminar task definitions
echo "→ Buscando task definitions..."
if [ ! -z "$TIMESTAMP_FILTER" ]; then
    TASK_DEFINITIONS=$(aws ecs list-task-definitions --query "taskDefinitionArns[?contains(@, 'demo-task-${TIMESTAMP_FILTER}')]" --output text)
else
    TASK_DEFINITIONS=$(aws ecs list-task-definitions --query "taskDefinitionArns[?contains(@, 'demo-task-')]" --output text)
fi

if [ ! -z "$TASK_DEFINITIONS" ]; then
    for TASK_DEF in $TASK_DEFINITIONS; do
        echo "  Desregistrando task definition..."
        aws ecs deregister-task-definition --task-definition $TASK_DEF >/dev/null 2>&1
        print_status $? "Task definition desregistrada"
        ((TOTAL_DELETED++))
    done
else
    echo "  No se encontraron task definitions"
fi

# =================================================================
# LIMPIEZA ECR
# =================================================================

echo -e "\n${BLUE}[3/8] Limpiando repositorios ECR...${NC}"

echo "→ Buscando repositorios ECR..."
if [ ! -z "$TIMESTAMP_FILTER" ]; then
    ECR_REPOS=$(aws ecr describe-repositories --query "repositories[?contains(repositoryName, 'demo-ecs-${TIMESTAMP_FILTER}')].repositoryName" --output text 2>/dev/null)
else
    ECR_REPOS=$(aws ecr describe-repositories --query "repositories[?contains(repositoryName, 'demo-ecs-')].repositoryName" --output text 2>/dev/null)
fi

if [ ! -z "$ECR_REPOS" ]; then
    for REPO in $ECR_REPOS; do
        echo "  Eliminando repositorio: $REPO"
        aws ecr delete-repository --repository-name $REPO --force >/dev/null 2>&1
        print_status $? "Repositorio $REPO eliminado"
        ((TOTAL_DELETED++))
    done
else
    echo "  No se encontraron repositorios ECR"
fi

# =================================================================
# LIMPIEZA LAMBDA
# =================================================================

echo -e "\n${BLUE}[4/8] Limpiando funciones Lambda...${NC}"

echo "→ Buscando funciones Lambda..."
if [ ! -z "$TIMESTAMP_FILTER" ]; then
    LAMBDA_FUNCTIONS=$(aws lambda list-functions --query "Functions[?contains(FunctionName, 'demo-lambda-${TIMESTAMP_FILTER}')].FunctionName" --output text)
else
    LAMBDA_FUNCTIONS=$(aws lambda list-functions --query "Functions[?contains(FunctionName, 'demo-lambda-')].FunctionName" --output text)
fi

if [ ! -z "$LAMBDA_FUNCTIONS" ]; then
    for FUNCTION in $LAMBDA_FUNCTIONS; do
        echo "  Eliminando función: $FUNCTION"
        
        # Eliminar Function URL si existe
        aws lambda delete-function-url-config --function-name $FUNCTION >/dev/null 2>&1
        
        # Eliminar la función
        aws lambda delete-function --function-name $FUNCTION >/dev/null 2>&1
        print_status $? "Función $FUNCTION eliminada"
        ((TOTAL_DELETED++))
    done
else
    echo "  No se encontraron funciones Lambda"
fi

# =================================================================
# LIMPIEZA API GATEWAY
# =================================================================

echo -e "\n${BLUE}[5/8] Limpiando API Gateways...${NC}"

echo "→ Buscando API Gateways..."
if [ ! -z "$TIMESTAMP_FILTER" ]; then
    API_IDS=$(aws apigatewayv2 get-apis --query "Items[?contains(Name, 'demo-api-${TIMESTAMP_FILTER}')].ApiId" --output text 2>/dev/null)
else
    API_IDS=$(aws apigatewayv2 get-apis --query "Items[?contains(Name, 'demo-api-')].ApiId" --output text 2>/dev/null)
fi

if [ ! -z "$API_IDS" ]; then
    for API_ID in $API_IDS; do
        echo "  Eliminando API: $API_ID"
        aws apigatewayv2 delete-api --api-id $API_ID >/dev/null 2>&1
        print_status $? "API $API_ID eliminada"
        ((TOTAL_DELETED++))
    done
else
    echo "  No se encontraron API Gateways"
fi

# =================================================================
# LIMPIEZA S3
# =================================================================

echo -e "\n${BLUE}[6/8] Limpiando buckets S3...${NC}"

echo "→ Buscando buckets S3..."
if [ ! -z "$TIMESTAMP_FILTER" ]; then
    S3_BUCKETS=$(aws s3 ls | grep "aws-demo-.*-${TIMESTAMP_FILTER}" | awk '{print $3}')
else
    S3_BUCKETS=$(aws s3 ls | grep "aws-demo-" | awk '{print $3}')
fi

if [ ! -z "$S3_BUCKETS" ]; then
    for BUCKET in $S3_BUCKETS; do
        echo "  Vaciando y eliminando bucket: $BUCKET"
        
        # Vaciar el bucket
        aws s3 rm s3://$BUCKET --recursive >/dev/null 2>&1
        
        # Eliminar versiones si el versionado está habilitado
        aws s3api delete-objects \
            --bucket $BUCKET \
            --delete "$(aws s3api list-object-versions \
            --bucket $BUCKET \
            --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" >/dev/null 2>&1
        
        # Eliminar el bucket
        aws s3 rb s3://$BUCKET --force >/dev/null 2>&1
        print_status $? "Bucket $BUCKET eliminado"
        ((TOTAL_DELETED++))
    done
else
    echo "  No se encontraron buckets S3"
fi

# =================================================================
# LIMPIEZA IAM
# =================================================================

echo -e "\n${BLUE}[7/8] Limpiando roles IAM...${NC}"

# Roles de Lambda
echo "→ Buscando roles Lambda..."
if [ ! -z "$TIMESTAMP_FILTER" ]; then
    LAMBDA_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, 'lambda-demo-role-${TIMESTAMP_FILTER}')].RoleName" --output text)
else
    LAMBDA_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, 'lambda-demo-role-')].RoleName" --output text)
fi

if [ ! -z "$LAMBDA_ROLES" ]; then
    for ROLE in $LAMBDA_ROLES; do
        echo "  Eliminando rol Lambda: $ROLE"
        
        # Detach policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name $ROLE --query 'AttachedPolicies[].PolicyArn' --output text)
        for POLICY in $ATTACHED_POLICIES; do
            aws iam detach-role-policy --role-name $ROLE --policy-arn $POLICY >/dev/null 2>&1
        done
        
        # Delete role
        aws iam delete-role --role-name $ROLE >/dev/null 2>&1
        print_status $? "Rol $ROLE eliminado"
        ((TOTAL_DELETED++))
    done
else
    echo "  No se encontraron roles Lambda"
fi

# Roles de ECS
echo "→ Buscando roles ECS..."
if [ ! -z "$TIMESTAMP_FILTER" ]; then
    ECS_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, 'ecsTaskExecutionRole-${TIMESTAMP_FILTER}')].RoleName" --output text)
else
    ECS_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, 'ecsTaskExecutionRole-')].RoleName" --output text)
fi

if [ ! -z "$ECS_ROLES" ]; then
    for ROLE in $ECS_ROLES; do
        echo "  Eliminando rol ECS: $ROLE"
        
        # Detach policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name $ROLE --query 'AttachedPolicies[].PolicyArn' --output text)
        for POLICY in $ATTACHED_POLICIES; do
            aws iam detach-role-policy --role-name $ROLE --policy-arn $POLICY >/dev/null 2>&1
        done
        
        # Delete role
        aws iam delete-role --role-name $ROLE >/dev/null 2>&1
        print_status $? "Rol $ROLE eliminado"
        ((TOTAL_DELETED++))
    done
else
    echo "  No se encontraron roles ECS"
fi

# =================================================================
# LIMPIEZA CLOUDWATCH LOGS
# =================================================================

echo -e "\n${BLUE}[8/8] Limpiando CloudWatch Logs...${NC}"

echo "→ Buscando log groups..."

# Logs de Lambda
if [ ! -z "$TIMESTAMP_FILTER" ]; then
    LAMBDA_LOGS=$(aws logs describe-log-groups --query "logGroups[?contains(logGroupName, '/aws/lambda/demo-lambda-${TIMESTAMP_FILTER}')].logGroupName" --output text)
else
    LAMBDA_LOGS=$(aws logs describe-log-groups --query "logGroups[?contains(logGroupName, '/aws/lambda/demo-lambda-')].logGroupName" --output text)
fi

if [ ! -z "$LAMBDA_LOGS" ]; then
    for LOG_GROUP in $LAMBDA_LOGS; do
        echo "  Eliminando log group: $LOG_GROUP"
        aws logs delete-log-group --log-group-name $LOG_GROUP >/dev/null 2>&1
        print_status $? "Log group eliminado"
        ((TOTAL_DELETED++))
    done
fi

# Logs de ECS
if [ ! -z "$TIMESTAMP_FILTER" ]; then
    ECS_LOGS=$(aws logs describe-log-groups --query "logGroups[?contains(logGroupName, '/ecs/demo-${TIMESTAMP_FILTER}')].logGroupName" --output text)
else
    ECS_LOGS=$(aws logs describe-log-groups --query "logGroups[?contains(logGroupName, '/ecs/demo-')].logGroupName" --output text)
fi

if [ ! -z "$ECS_LOGS" ]; then
    for LOG_GROUP in $ECS_LOGS; do
        echo "  Eliminando log group: $LOG_GROUP"
        aws logs delete-log-group --log-group-name $LOG_GROUP >/dev/null 2>&1
        print_status $? "Log group eliminado"
        ((TOTAL_DELETED++))
    done
fi

# =================================================================
# LIMPIEZA SECURITY GROUPS Y KEY PAIRS
# =================================================================

echo -e "\n${BLUE}[FINAL] Limpiando Security Groups y Key Pairs...${NC}"

# Esperar un momento para asegurar que las instancias están terminadas
sleep 5

# Security Groups
echo "→ Buscando Security Groups..."
if [ ! -z "$TIMESTAMP_FILTER" ]; then
    SG_IDS=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=aws-demo-sg-${TIMESTAMP_FILTER}" --query 'SecurityGroups[].GroupId' --output text)
else
    SG_IDS=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=aws-demo-sg-*" --query 'SecurityGroups[].GroupId' --output text)
fi

if [ ! -z "$SG_IDS" ]; then
    for SG_ID in $SG_IDS; do
        echo "  Eliminando Security Group: $SG_ID"
        aws ec2 delete-security-group --group-id $SG_ID >/dev/null 2>&1
        print_status $? "Security Group $SG_ID eliminado"
        ((TOTAL_DELETED++))
    done
else
    echo "  No se encontraron Security Groups"
fi

# Key Pairs
echo "→ Buscando Key Pairs..."
if [ ! -z "$TIMESTAMP_FILTER" ]; then
    KEY_PAIRS=$(aws ec2 describe-key-pairs --filters "Name=key-name,Values=aws-demo-key-${TIMESTAMP_FILTER}" --query 'KeyPairs[].KeyName' --output text)
else
    KEY_PAIRS=$(aws ec2 describe-key-pairs --filters "Name=key-name,Values=aws-demo-key-*" --query 'KeyPairs[].KeyName' --output text)
fi

if [ ! -z "$KEY_PAIRS" ]; then
    for KEY_NAME in $KEY_PAIRS; do
        echo "  Eliminando Key Pair: $KEY_NAME"
        aws ec2 delete-key-pair --key-name $KEY_NAME >/dev/null 2>&1
        print_status $? "Key Pair $KEY_NAME eliminado"
        
        # Eliminar archivo .pem local si existe
        if [ -f "${KEY_NAME}.pem" ]; then
            rm -f "${KEY_NAME}.pem"
            echo "    Archivo local ${KEY_NAME}.pem eliminado"
        fi
        ((TOTAL_DELETED++))
    done
else
    echo "  No se encontraron Key Pairs"
fi

# =================================================================
# RESUMEN FINAL
# =================================================================

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}              LIMPIEZA COMPLETADA${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Recursos eliminados exitosamente: ${GREEN}${TOTAL_DELETED}${NC}"
echo -e "Recursos con errores: ${RED}${TOTAL_FAILED}${NC}"
echo ""

if [ $TOTAL_FAILED -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Algunos recursos no pudieron ser eliminados.${NC}"
    echo -e "${YELLOW}   Esto puede deberse a dependencias o permisos.${NC}"
    echo -e "${YELLOW}   Verifica manualmente en la consola AWS.${NC}"
else
    echo -e "${GREEN}✓ Todos los recursos fueron eliminados exitosamente.${NC}"
fi

echo ""
echo -e "${BLUE}Recursos que deberías verificar manualmente:${NC}"
echo "  • EC2: Instancias, Volúmenes EBS, Elastic IPs"
echo "  • ECS: Clusters, Task Definitions, Services"
echo "  • Lambda: Functions, Layers, Event Source Mappings"
echo "  • S3: Buckets con versioning o políticas especiales"
echo "  • CloudWatch: Logs, Métricas, Alarmas"
echo "  • IAM: Roles y políticas adicionales"
echo ""

# Verificación adicional de costos
echo -e "${YELLOW}💰 Para verificar costos pendientes:${NC}"
echo "   aws ce get-cost-and-usage \\"
echo "     --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \\"
echo "     --granularity DAILY \\"
echo "     --metrics UnblendedCost \\"
echo "     --filter file://cost-filter.json"
echo ""

echo "Script de limpieza finalizado."
