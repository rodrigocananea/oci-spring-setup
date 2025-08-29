#!/bin/bash

# URL do script completo no GitHub Raw
SCRIPT_URL="https://raw.githubusercontent.com/rodrigocananea/oci-spring-setup/main/setup-spring-nginx-certbot.sh"

# Banner
echo "======================================================"
echo "  Spring Boot + Nginx + Certbot Setup Script"
echo "  Desenvolvido por: Rodrigo Cananea"
echo "======================================================"
echo

# Baixar e executar o script principal
echo "Baixando script de configuração..."
curl -sSL "$SCRIPT_URL" | bash

echo
echo "Script executado com sucesso!"
echo "Repositório: https://github.com/rodrigocananea/oci-spring-setup"
