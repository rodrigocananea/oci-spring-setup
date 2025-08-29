#!/bin/bash

# Cores para melhor visualização
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
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

log_header() {
    echo -e "${PURPLE}[HEADER]${NC} $1"
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

# Função para detectar o sistema operacional
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    elif [ -f /etc/redhat-release ]; then
        OS="Red Hat Enterprise Linux"
        VER=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
    elif [ -f /etc/debian_version ]; then
        OS="Debian"
        VER=$(cat /etc/debian_version)
    else
        OS=$(uname -s)
        VER=$(uname -r)
    fi
}

# Função para verificar versão do Ubuntu
check_ubuntu_version() {
    if [[ "$OS" == *"Ubuntu"* ]]; then
        UBUNTU_VERSION=$(echo $VER | cut -d. -f1)
        if [ "$UBUNTU_VERSION" -lt 22 ]; then
            log_warning "Você está usando Ubuntu $VER. É recomendado usar Ubuntu 22.04 LTS ou superior."
            if ! confirm "Deseja continuar mesmo assim?"; then
                log_error "Script cancelado pelo usuário."
                exit 1
            fi
        else
            log_success "Ubuntu $VER detectado - versão compatível!"
        fi
    else
        log_warning "Sistema operacional detectado: $OS $VER"
        log_warning "Este script foi otimizado para Ubuntu 22.04+ mas pode funcionar em outras distribuições."
        if ! confirm "Deseja continuar?"; then
            log_error "Script cancelado pelo usuário."
            exit 1
        fi
    fi
}

# Função para atualizar o sistema
update_system() {
    log_info "Atualizando sistema operacional..."

    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        sudo apt update && sudo apt upgrade -y
        validate_command "Sistema atualizado com sucesso" "Falha ao atualizar sistema"

        # Instalar dependências básicas
        sudo apt install -y curl wget gnupg lsb-release ca-certificates
        validate_command "Dependências básicas instaladas" "Falha ao instalar dependências básicas"

    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]] || [[ "$OS" == *"Rocky"* ]]; then
        sudo yum update -y
        validate_command "Sistema atualizado com sucesso" "Falha ao atualizar sistema"

        # Instalar dependências básicas
        sudo yum install -y curl wget gnupg ca-certificates
        validate_command "Dependências básicas instaladas" "Falha ao instalar dependências básicas"

    else
        log_warning "Sistema operacional não reconhecido para atualização automática."
        if confirm "Deseja tentar continuar sem atualizar o sistema?"; then
            log_info "Continuando sem atualização do sistema..."
        else
            exit 1
        fi
    fi
}

# Função para instalar Docker
install_docker() {
    log_info "Instalando Docker..."

    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        # Remover versões antigas
        sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

        # Adicionar repositório oficial do Docker
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]] || [[ "$OS" == *"Rocky"* ]]; then
        # Remover versões antigas
        sudo yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true

        # Instalar Docker
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi

    validate_command "Docker instalado com sucesso" "Falha ao instalar Docker"

    # Iniciar e habilitar Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    validate_command "Docker iniciado e habilitado" "Falha ao iniciar Docker"

    # Adicionar usuário ao grupo docker
    sudo usermod -aG docker $USER
    log_success "Usuário adicionado ao grupo docker"
    log_warning "Você precisará fazer logout/login ou usar 'newgrp docker' para aplicar as permissões do grupo"
}

# Função para instalar Docker Compose (standalone)
install_docker_compose() {
    log_info "Instalando Docker Compose standalone..."

    # Obter a versão mais recente
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)

    # Download e instalação
    sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose

    # Criar link simbólico se necessário
    sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

    validate_command "Docker Compose instalado com sucesso" "Falha ao instalar Docker Compose"
}

# Função para verificar recursos do sistema
check_system_requirements() {
    log_info "Verificando recursos do sistema..."

    # Verificar RAM
    TOTAL_RAM=$(free -m | awk 'NR==2{printf "%.0f", $2/1024}')
    if [ "$TOTAL_RAM" -lt 2 ]; then
        log_warning "Sistema tem ${TOTAL_RAM}GB de RAM. Recomendado: 2GB ou mais."
    else
        log_success "RAM disponível: ${TOTAL_RAM}GB"
    fi

    # Verificar espaço em disco
    DISK_SPACE=$(df -h / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "${DISK_SPACE%.*}" -lt 10 ]; then
        log_warning "Espaço disponível em disco: ${DISK_SPACE}G. Recomendado: 10GB ou mais."
    else
        log_success "Espaço em disco disponível: ${DISK_SPACE}G"
    fi

    # Verificar se as portas estão livres
    if ss -tulpn | grep -q ":80 "; then
        log_warning "Porta 80 já está em uso. Isso pode causar conflitos com o Nginx."
    fi

    if ss -tulpn | grep -q ":443 "; then
        log_warning "Porta 443 já está em uso. Isso pode causar conflitos com o Nginx HTTPS."
    fi
}

# Banner inicial melhorado
echo -e "${CYAN}"
echo "=================================================================="
echo "   🚀 Script de Configuração: Spring Boot + Nginx + Certbot     "
echo "=================================================================="
echo -e "${NC}"
echo -e "${BLUE}Desenvolvido por: rodrigocananea${NC}"
echo -e "${BLUE}Data: $(date '+%d/%m/%Y %H:%M:%S')${NC}"
echo
echo -e "${YELLOW}📋 REQUISITOS RECOMENDADOS:${NC}"
echo "  • Ubuntu 22.04 LTS ou superior"
echo "  • 2GB+ de RAM"
echo "  • 10GB+ de espaço em disco"
echo "  • Domínio apontando para este servidor"
echo "  • Portas 80 e 443 liberadas"
echo
echo -e "${YELLOW}⚠️  IMPORTANTE:${NC}"
echo "  • Execute este script como usuário não-root com sudo"
echo "  • Certifique-se de ter backup dos dados importantes"
echo "  • O script irá instalar/atualizar Docker se necessário"
echo

if ! confirm "Deseja continuar com a instalação?"; then
    log_error "Instalação cancelada pelo usuário."
    exit 0
fi

# Verificações do sistema
log_header "=== VERIFICAÇÕES DO SISTEMA ==="

# Detectar SO
detect_os
log_info "Sistema operacional detectado: $OS $VER"

# Verificar versão do Ubuntu
check_ubuntu_version

# Verificar se está executando como root
if [ "$EUID" -eq 0 ]; then
    log_error "Este script NÃO deve ser executado como root!"
    log_error "Execute como usuário normal com privilégios sudo."
    exit 1
fi

# Verificar se sudo está disponível
if ! command -v sudo &> /dev/null; then
    log_error "sudo não está instalado. Por favor, instale sudo primeiro."
    exit 1
fi

# Verificar recursos do sistema
check_system_requirements

# Atualizar sistema se solicitado
if confirm "Deseja atualizar o sistema operacional?"; then
    update_system
else
    log_info "Pulando atualização do sistema..."
fi

# Verificações e instalação do Docker
log_header "=== VERIFICAÇÃO E INSTALAÇÃO DO DOCKER ==="

# Verificar se o Docker está instalado
if ! command -v docker &> /dev/null; then
    log_warning "Docker não está instalado."
    if confirm "Deseja instalar o Docker automaticamente?"; then
        install_docker
    else
        log_error "Docker é necessário para continuar. Instale manualmente e execute o script novamente."
        exit 1
    fi
else
    DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
    log_success "Docker já está instalado: $DOCKER_VERSION"

    # Verificar se o Docker está rodando
    if ! docker info &> /dev/null; then
        log_info "Iniciando serviço Docker..."
        sudo systemctl start docker
        validate_command "Docker iniciado" "Falha ao iniciar Docker"
    fi
fi

# Verificar se o Docker Compose está instalado
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    log_warning "Docker Compose não está instalado."
    if confirm "Deseja instalar o Docker Compose automaticamente?"; then
        install_docker_compose
    else
        log_error "Docker Compose é necessário para continuar. Instale manualmente e execute o script novamente."
        exit 1
    fi
else
    if command -v docker-compose &> /dev/null; then
        COMPOSE_VERSION=$(docker-compose --version | cut -d' ' -f3 | cut -d',' -f1)
        log_success "Docker Compose já está instalado: $COMPOSE_VERSION"
    else
        COMPOSE_VERSION=$(docker compose version --short)
        log_success "Docker Compose (plugin) já está instalado: $COMPOSE_VERSION"
    fi
fi

# Verificar permissões do Docker
log_info "Verificando permissões do Docker..."
if docker ps &> /dev/null; then
    log_success "Permissões do Docker OK"
else
    log_warning "Usuário não tem permissões para usar Docker sem sudo"
    if confirm "Deseja adicionar o usuário atual ao grupo docker?"; then
        sudo usermod -aG docker $USER
        log_success "Usuário adicionado ao grupo docker"
        log_warning "IMPORTANTE: Faça logout/login ou execute 'newgrp docker' para aplicar as permissões"
        log_warning "Ou execute o Docker com sudo durante esta sessão"
    fi
fi

log_header "=== COLETA DE INFORMAÇÕES ==="

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

# Resumo das configurações
echo
log_header "=== RESUMO DAS CONFIGURAÇÕES ==="
echo -e "${CYAN}Projeto:${NC} $PROJECT_NAME"
echo -e "${CYAN}Domínio:${NC} $DOMAIN_NAME"
echo -e "${CYAN}Rede Docker:${NC} $NETWORK_NAME"
echo -e "${CYAN}Container Spring:${NC} $CONTAINER_NAME"
echo -e "${CYAN}Imagem Spring:${NC} $IMAGE_NAME"
echo -e "${CYAN}Email Certbot:${NC} $EMAIL"
echo -e "${CYAN}PostgreSQL:${NC} $POSTGRES_USER@$POSTGRES_DB (porta $POSTGRES_PORT)"
echo

if ! confirm "As configurações estão corretas?"; then
    log_error "Configuração cancelada pelo usuário."
    exit 0
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

log_header "=== PASSO 1: Configuração inicial para geração de certificados SSL ==="

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

# Determinar comando do Docker Compose
COMPOSE_CMD="docker-compose"
if ! command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker compose"
fi

# Subir containers iniciais
log_info "Subindo containers iniciais..."
$COMPOSE_CMD up -d
validate_command "Containers iniciais iniciados" "Falha ao iniciar containers iniciais"

# Aguardar containers iniciarem
log_info "Aguardando containers iniciarem..."
sleep 10

# Gerar certificados SSL
log_info "Gerando certificados SSL com Certbot..."
if docker run --rm \
    -v "$(pwd)/nginx/certbot:/var/www/certbot" \
    -v "$(pwd)/nginx/certbot-etc:/etc/letsencrypt" \
    certbot/certbot certonly --webroot \
    -w /var/www/certbot \
    -d "$DOMAIN_NAME" \
    --email "$EMAIL" --agree-tos --no-eff-email; then
    log_success "Certificados SSL gerados com sucesso"
else
    log_error "Falha ao gerar certificados SSL. Verifique se o domínio está apontando para este servidor."
    log_info "Continuando mesmo assim para configurar o ambiente..."
fi

log_header "=== PASSO 2: Configuração final para servir o App Spring Boot ==="

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
$COMPOSE_CMD down
validate_command "Containers parados" "Falha ao parar containers"

$COMPOSE_CMD up -d
validate_command "Containers reiniciados" "Falha ao reiniciar containers"

# Aguardar serviços iniciarem
log_info "Aguardando serviços iniciarem..."
sleep 15

# Validações finais
log_header "=== VALIDAÇÕES FINAIS ==="

# Verificar se os containers estão rodando
log_info "Verificando status dos containers..."
if $COMPOSE_CMD ps | grep -q "Up"; then
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
echo "3. Monitore os logs com: cd $PROJECT_PATH && $COMPOSE_CMD logs -f"
echo
echo -e "${BLUE}Comandos úteis:${NC}"
echo "- Ver status: cd $PROJECT_PATH && $COMPOSE_CMD ps"
echo "- Ver logs: cd $PROJECT_PATH && $COMPOSE_CMD logs -f"
echo "- Parar serviços: cd $PROJECT_PATH && $COMPOSE_CMD down"
echo "- Iniciar serviços: cd $PROJECT_PATH && $COMPOSE_CMD up -d"
echo

# Salvar configurações em arquivo de resumo
cat > "$PROJECT_PATH/CONFIGURACAO.md" << EOF
# Configuração do Ambiente

## Informações do Sistema
- **SO**: $OS $VER
- **Data da Instalação**: $(date '+%d/%m/%Y %H:%M:%S')
- **Usuário**: $USER

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
$COMPOSE_CMD ps

# Ver logs
$COMPOSE_CMD logs -f

# Parar serviços
$COMPOSE_CMD down

# Iniciar serviços
$COMPOSE_CMD up -d

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

## Troubleshooting
- **Containers não iniciam**: Verifique logs com \`$COMPOSE_CMD logs\`
- **SSL não funciona**: Verifique se o domínio aponta para o servidor
- **Aplicação não carrega**: Verifique se a imagem existe e se as variáveis de ambiente estão corretas
EOF

log_success "Arquivo de configuração salvo em: $PROJECT_PATH/CONFIGURACAO.md"

# Criar script de manutenção
cat > "$PROJECT_PATH/manutencao.sh" << EOF
#!/bin/bash

# Script de manutenção para $PROJECT_NAME
cd "$PROJECT_PATH"

case \$1 in
    "start")
        echo "Iniciando serviços..."
        $COMPOSE_CMD up -d
        ;;
    "stop")
        echo "Parando serviços..."
        $COMPOSE_CMD down
        ;;
    "restart")
        echo "Reiniciando serviços..."
        $COMPOSE_CMD down && $COMPOSE_CMD up -d
        ;;
    "logs")
        $COMPOSE_CMD logs -f
        ;;
    "status")
        $COMPOSE_CMD ps
        ;;
    "renew-ssl")
        echo "Renovando certificados SSL..."
        docker run --rm -v "\$(pwd)/nginx/certbot:/var/www/certbot" -v "\$(pwd)/nginx/certbot-etc:/etc/letsencrypt" certbot/certbot renew
        $COMPOSE_CMD restart nginx
        ;;
    *)
        echo "Uso: \$0 {start|stop|restart|logs|status|renew-ssl}"
        ;;
esac
EOF

chmod +x "$PROJECT_PATH/manutencao.sh"
log_success "Script de manutenção criado: $PROJECT_PATH/manutencao.sh"

echo
echo -e "${CYAN}🎉 Instalação concluída com sucesso!${NC}"
echo -e "${YELLOW}📝 Não esqueça de fazer logout/login para aplicar as permissões do Docker (se necessário)${NC}"
