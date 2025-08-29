#!/bin/bash

# Cores para melhor visualização
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para log colorido
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Função para validar se um comando foi executado com sucesso
validate_command() {
    if [ $? -eq 0 ]; then
        log_success "$1"
    else
        log_error "$2"
        exit 1
    fi
}

# Função para solicitar input com validação
get_input() {
    local prompt="$1"
    local var_name="$2"
    local validation="$3"
    local value
    
    while true; do
        echo -e "${YELLOW}$prompt${NC}"
        read -r value
        
        if [ "$validation" = "required" ] && [ -z "$value" ]; then
            log_error "Este campo é obrigatório!"
            continue
        fi
        
        if [ "$validation" = "email" ]; then
            if [[ ! "$value" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                log_error "Email inválido!"
                continue
            fi
        fi
        
        if [ "$validation" = "domain" ]; then
            if [[ ! "$value" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                log_error "Domínio inválido!"
                continue
            fi
        fi
        
        eval "$var_name='$value'"
        break
    done
}

# Função para solicitar confirmação
confirm() {
    local prompt="$1"
    local response
    
    while true; do
        echo -e "${YELLOW}$prompt (s/n):${NC}"
        read -r response
        case $response in
            [Ss]* ) return 0;;
            [Nn]* ) return 1;;
            * ) log_warning "Por favor, responda com 's' ou 'n'.";;
        esac
    done
}

# Banner inicial
echo -e "${BLUE}"
echo "============================================================"
echo "  Script de Configuração: Spring Boot + Nginx + Certbot   "
echo "============================================================"
echo -e "${NC}"

# Verificar se está executando como root ou com sudo
if [ "$EUID" -eq 0 ]; then
    log_warning "Este script está sendo executado como root. Certifique-se de que isso é necessário."
fi

# Verificar se o Docker está instalado
if ! command -v docker &> /dev/null; then
    log_error "Docker não está instalado. Por favor, instale o Docker primeiro."
    exit 1
fi

# Verificar se o Docker Compose está instalado
if ! command -v docker-compose &> /dev/null; then
    log_error "Docker Compose não está instalado. Por favor, instale o Docker Compose primeiro."
    exit 1
fi

log_info "Coletando informações necessárias..."

# Coleta de informações
get_input "Digite o nome da pasta para criar o projeto (será criada em /home/ubuntu/):" PROJECT_NAME "required"
get_input "Digite o nome do domínio (ex: meudominio.com.br):" DOMAIN_NAME "domain"
get_input "Digite o nome da rede Docker (padrão: net-appspring):" NETWORK_NAME "required"
get_input "Digite seu email para o Certbot:" EMAIL "email"
get_input "Digite o nome do container Spring Boot (padrão: container-appspring):" CONTAINER_NAME "required"
get_input "Digite o nome da imagem Docker para o Spring Boot:" IMAGE_NAME "required"

echo -e "${YELLOW}Digite as variáveis de ambiente separadas por ';' (ex: ENV1=value1;ENV2=value2):${NC}"
read -r ENVIRONMENTS

# Configurações do PostgreSQL
log_info "Configurações do PostgreSQL:"
get_input "POSTGRES_PASSWORD:" POSTGRES_PASSWORD "required"
get_input "POSTGRES_USER:" POSTGRES_USER "required"
get_input "POSTGRES_DB:" POSTGRES_DB "required"
get_input "Porta externa do PostgreSQL (padrão: 5497):" POSTGRES_PORT "required"
get_input "Porta de expose do PostgreSQL (padrão: 5497):" POSTGRES_EXPOSE "required"

# Configurações de porta do Spring Boot
if confirm "Deseja expor alguma porta para o Spring Boot?"; then
    get_input "Digite a porta para expose:" SPRING_EXPOSE "required"
    SPRING_PORTS_CONFIG="ports:\n      - $SPRING_EXPOSE:8080"
    SPRING_EXPOSE_CONFIG="expose:\n      - $SPRING_EXPOSE"
else
    SPRING_PORTS_CONFIG=""
    SPRING_EXPOSE_CONFIG="expose:\n      - 8080"
fi

# Criar diretório do projeto
PROJECT_PATH="/home/ubuntu/$PROJECT_NAME"
log_info "Criando diretório do projeto: $PROJECT_PATH"

if [ -d "$PROJECT_PATH" ]; then
    if confirm "O diretório $PROJECT_PATH já existe. Deseja continuar e sobrescrever?"; then
        rm -rf "$PROJECT_PATH"
    else
        log_error "Operação cancelada pelo usuário."
        exit 1
    fi
fi

mkdir -p "$PROJECT_PATH"
cd "$PROJECT_PATH"
validate_command "Diretório do projeto criado com sucesso" "Falha ao criar diretório do projeto"

# Criar estrutura de diretórios
log_info "Criando estrutura de diretórios..."
mkdir -p nginx/conf.d nginx/certbot nginx/certbot-etc app
validate_command "Estrutura de diretórios criada" "Falha ao criar estrutura de diretórios"

# Processar variáveis de ambiente
ENVIRONMENT_VARS=""
if [ -n "$ENVIRONMENTS" ]; then
    IFS=';' read -ra ENV_ARRAY <<< "$ENVIRONMENTS"
    for env in "${ENV_ARRAY[@]}"; do
        if [ -n "$env" ]; then
            ENVIRONMENT_VARS="$ENVIRONMENT_VARS      - $env\n"
        fi
    done
fi

log_info "=== PASSO 1: Configuração inicial para geração de certificados SSL ==="

# Criar docker-compose.yml inicial
log_info "Criando docker-compose.yml inicial..."
cat > docker-compose.yml << EOF
services:
  nginx:
    image: nginx:latest
    container_name: nginx-proxy
    ports:
      - 80:80
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/certbot:/var/www/certbot
    networks:
      - $NETWORK_NAME

  certbot:
    image: certbot/certbot:latest
    container_name: certbot
    volumes:
      - ./nginx/certbot:/var/www/certbot
      - ./nginx/certbot-etc:/etc/letsencrypt
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do sleep 5; done'"
    networks:
      - $NETWORK_NAME

networks:
  $NETWORK_NAME:
    driver: bridge
EOF
validate_command "docker-compose.yml inicial criado" "Falha ao criar docker-compose.yml inicial"

# Criar configuração inicial do Nginx
log_info "Criando configuração inicial do Nginx..."
cat > nginx/conf.d/default.conf << EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;

    # Local para o Certbot validar os desafios
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Retornará 404 para qualquer outra rota
    location / {
        return 404;
    }
}
EOF
validate_command "Configuração inicial do Nginx criada" "Falha ao criar configuração inicial do Nginx"

# Subir containers iniciais
log_info "Subindo containers iniciais..."
docker-compose up -d
validate_command "Containers iniciais iniciados" "Falha ao iniciar containers iniciais"

# Aguardar containers iniciarem
log_info "Aguardando containers iniciarem..."
sleep 10

# Gerar certificados SSL
log_info "Gerando certificados SSL com Certbot..."
docker run --rm \
    -v "$(pwd)/nginx/certbot:/var/www/certbot" \
    -v "$(pwd)/nginx/certbot-etc:/etc/letsencrypt" \
    certbot/certbot certonly --webroot \
    -w /var/www/certbot \
    -d "$DOMAIN_NAME" \
    --email "$EMAIL" --agree-tos --no-eff-email

if [ $? -eq 0 ]; then
    log_success "Certificados SSL gerados com sucesso"
else
    log_error "Falha ao gerar certificados SSL. Verifique se o domínio está apontando para este servidor."
    log_info "Continuando mesmo assim para configurar o ambiente..."
fi

log_info "=== PASSO 2: Configuração final para servir o App Spring Boot ==="

# Atualizar configuração do Nginx
log_info "Atualizando configuração do Nginx para HTTPS..."
cat > nginx/conf.d/default.conf << EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;

    # Redireciona todo o tráfego HTTP para HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN_NAME;

    # Certificados SSL
    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;

    # Configurações adicionais de SSL
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Proxy para o app Spring Boot
    location / {
        proxy_pass http://$CONTAINER_NAME:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
validate_command "Configuração final do Nginx criada" "Falha ao criar configuração final do Nginx"

# Criar docker-compose.yml final
log_info "Criando docker-compose.yml final..."
cat > docker-compose.yml << EOF
services:
  nginx:
    image: nginx:latest
    container_name: nginx-proxy
    ports:
      - 80:80
      - 443:443
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/certbot:/var/www/certbot
      - ./nginx/certbot-etc:/etc/letsencrypt
    networks:
      - $NETWORK_NAME

  certbot:
    image: certbot/certbot:latest
    container_name: certbot
    volumes:
      - ./nginx/certbot:/var/www/certbot
      - ./nginx/certbot-etc:/etc/letsencrypt
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do sleep 5; done'"
    networks:
      - $NETWORK_NAME

  postgres:
    image: postgres:15
    networks:
      - $NETWORK_NAME
    container_name: postgres
    volumes:
      - postgres-data:/var/lib/postgresql/data
    expose:
      - $POSTGRES_EXPOSE
    ports:
      - $POSTGRES_PORT:5432
    environment:
      - POSTGRES_PASSWORD=$POSTGRES_PASSWORD
      - POSTGRES_USER=$POSTGRES_USER
      - POSTGRES_DB=$POSTGRES_DB
      - TZ=America/Sao_Paulo
    restart: unless-stopped

  $CONTAINER_NAME:
    image: $IMAGE_NAME
    container_name: $CONTAINER_NAME
    volumes:
      - /logs:/logs
    environment:
$(echo -e "$ENVIRONMENT_VARS")
    $(echo -e "$SPRING_EXPOSE_CONFIG")
$([ -n "$SPRING_PORTS_CONFIG" ] && echo -e "    $SPRING_PORTS_CONFIG")
    depends_on:
      - postgres
    networks:
      - $NETWORK_NAME

networks:
  $NETWORK_NAME:
    driver: bridge

volumes:
  postgres-data:
EOF
validate_command "docker-compose.yml final criado" "Falha ao criar docker-compose.yml final"

# Reiniciar serviços
log_info "Reiniciando serviços com nova configuração..."
docker-compose down
validate_command "Containers parados" "Falha ao parar containers"

docker-compose up -d
validate_command "Containers reiniciados" "Falha ao reiniciar containers"

# Aguardar serviços iniciarem
log_info "Aguardando serviços iniciarem..."
sleep 15

# Validações finais
log_info "=== VALIDAÇÕES FINAIS ==="

# Verificar se os containers estão rodando
log_info "Verificando status dos containers..."
if docker-compose ps | grep -q "Up"; then
    log_success "Containers estão executando"
else
    log_warning "Alguns containers podem não estar executando corretamente"
fi

# Verificar se o Nginx está respondendo
log_info "Testando conectividade HTTP..."
if curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN_NAME" | grep -q "301\|200"; then
    log_success "Nginx está respondendo corretamente"
else
    log_warning "Nginx pode não estar respondendo corretamente"
fi

# Verificar se o PostgreSQL está acessível
log_info "Testando conectividade com PostgreSQL..."
if docker exec postgres pg_isready -U "$POSTGRES_USER" > /dev/null 2>&1; then
    log_success "PostgreSQL está acessível"
else
    log_warning "PostgreSQL pode não estar acessível"
fi

# Verificar certificados SSL
log_info "Verificando certificados SSL..."
if [ -f "nginx/certbot-etc/live/$DOMAIN_NAME/fullchain.pem" ]; then
    log_success "Certificados SSL encontrados"
else
    log_warning "Certificados SSL não encontrados. Pode ser necessário configurar DNS primeiro."
fi

# Resumo final
echo
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}               CONFIGURAÇÃO CONCLUÍDA!                    ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo
log_info "Diretório do projeto: $PROJECT_PATH"
log_info "Domínio configurado: $DOMAIN_NAME"
log_info "Rede Docker: $NETWORK_NAME"
log_info "Container Spring Boot: $CONTAINER_NAME"
log_info "PostgreSQL User: $POSTGRES_USER"
log_info "PostgreSQL Database: $POSTGRES_DB"
log_info "PostgreSQL Port: $POSTGRES_PORT"
echo
echo -e "${YELLOW}Próximos passos:${NC}"
echo "1. Certifique-se de que o DNS do domínio $DOMAIN_NAME aponta para este servidor"
echo "2. Acesse https://$DOMAIN_NAME para testar o aplicativo"
echo "3. Monitore os logs com: cd $PROJECT_PATH && docker-compose logs -f"
echo
echo -e "${BLUE}Comandos úteis:${NC}"
echo "- Ver status: cd $PROJECT_PATH && docker-compose ps"
echo "- Ver logs: cd $PROJECT_PATH && docker-compose logs -f"
echo "- Parar serviços: cd $PROJECT_PATH && docker-compose down"
echo "- Iniciar serviços: cd $PROJECT_PATH && docker-compose up -d"
echo

# Salvar configurações em arquivo de resumo
cat > "$PROJECT_PATH/CONFIGURACAO.md" << EOF
# Configuração do Ambiente

## Informações do Projeto
- **Diretório**: $PROJECT_PATH
- **Domínio**: $DOMAIN_NAME
- **Rede Docker**: $NETWORK_NAME
- **Email Certbot**: $EMAIL

## Spring Boot
- **Container**: $CONTAINER_NAME
- **Imagem**: $IMAGE_NAME
- **Porta Expose**: $(echo -e "$SPRING_EXPOSE_CONFIG" | grep -o '[0-9]*' | head -1)

## PostgreSQL
- **Usuário**: $POSTGRES_USER
- **Database**: $POSTGRES_DB
- **Porta Externa**: $POSTGRES_PORT
- **Porta Expose**: $POSTGRES_EXPOSE

## Comandos Úteis
\`\`\`bash
# Navegar para o projeto
cd $PROJECT_PATH

# Ver status dos containers
docker-compose ps

# Ver logs
docker-compose logs -f

# Parar serviços
docker-compose down

# Iniciar serviços
docker-compose up -d

# Renovar certificados SSL
docker run --rm -v "\$(pwd)/nginx/certbot:/var/www/certbot" -v "\$(pwd)/nginx/certbot-etc:/etc/letsencrypt" certbot/certbot renew
\`\`\`

## Estrutura de Arquivos
\`\`\`
$PROJECT_NAME/
├── docker-compose.yml
├── nginx/
│   ├── conf.d/
│   │   └── default.conf
│   ├── certbot/
│   └── certbot-etc/
└── CONFIGURACAO.md
\`\`\`
EOF

log_success "Arquivo de configuração salvo em: $PROJECT_PATH/CONFIGURACAO.md"