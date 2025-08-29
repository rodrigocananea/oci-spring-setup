# Guia de Configuração: Docker Compose com Nginx, Certbot e App Spring Boot

Este guia detalha os passos para configurar um ambiente com **Nginx**, **Certbot** e um aplicativo Spring Boot rodando na porta 8080, utilizando **Docker Compose**. O processo está dividido em duas etapas principais: **configuração inicial para geração de certificados SSL** e **configuração final para servir o aplicativo com HTTPS**.

---

## **Passo 1: Configurar o Nginx para permitir a geração de certificados SSL com Certbot**

No primeiro momento, o Nginx será configurado apenas para permitir que o Certbot acesse as rotas necessárias para validar o domínio e gerar os certificados SSL.

### **1. Estrutura do Projeto**

Certifique-se de que sua estrutura de diretórios seja semelhante a esta:

```plaintext
project/
├── docker-compose.yml
├── nginx/
│   ├── conf.d/
│   │   └── default.conf
│   ├── certbot/
│   │   └── challenge/
└── app/
    ├── Dockerfile
    └── target/
        └── app.jar
```

### **2. Criar o Arquivo `docker-compose.yml`**

Use o comando abaixo para criar o arquivo `docker-compose.yml`:

```bash
cat <<EOF > docker-compose.yml
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
      - net-appspring

  certbot:
    image: certbot/certbot:latest
    container_name: certbot
    volumes:
      - ./nginx/certbot:/var/www/certbot
      - ./nginx/certbot-etc:/etc/letsencrypt
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do sleep 5; done'"
    networks:
      - net-appspring

networks:
  net-appspring:
    driver: bridge
EOF
```

### **3. Configuração Inicial do Nginx**

Use o comando abaixo para criar o arquivo `nginx/conf.d/default.conf`:

```bash
mkdir -p nginx/conf.d nginx/certbot nginx/certbot-etc

cat <<EOF > nginx/conf.d/default.conf
server {
    listen 80;
    server_name meudominio.com.br;

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
```

### **4. Subir os Containers**

Inicie os serviços do Docker Compose:

```bash
docker-compose up -d
```

### **5. Gerar os Certificados SSL com Certbot**

Execute o comando abaixo para gerar os certificados SSL para o domínio `meudominio.com.br`:

- Substitua:
    - `meudominio.com.br` pelo seu domínio.
    - `seuemail@exemplo.com` pelo seu email.

```bash
docker run --rm \
    -v "$(pwd)/nginx/certbot:/var/www/certbot" \
    -v "$(pwd)/nginx/certbot-etc:/etc/letsencrypt" \
    certbot/certbot certonly --webroot \
    -w /var/www/certbot \
    -d meudominio.com.br \
    --email seuemail@exemplo.com --agree-tos --no-eff-email
```

Os certificados SSL serão salvos no diretório `nginx/certbot-etc`.

---

## **Passo 2: Configurar o Nginx para Servir o App Spring Boot**

Após obter os certificados SSL, você pode alterar a configuração do Nginx para servir o aplicativo Spring Boot.

### **1. Atualizar o `default.conf` do Nginx**

Use o comando abaixo para atualizar o arquivo `nginx/conf.d/default.conf`:

```bash
cat <<EOF > nginx/conf.d/default.conf
server {
    listen 80;
    server_name meudominio.com.br;

    # Redireciona todo o tráfego HTTP para HTTPS
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name meudominio.com.br;

    # Certificados SSL
    ssl_certificate /etc/letsencrypt/live/meudominio.com.br/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/meudominio.com.br/privkey.pem;

    # Configurações adicionais de SSL
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Proxy para o app Spring Boot
    location / {
        proxy_pass http://container-appspring:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
```

### **2. Atualizar o `docker-compose.yml`**

Use o comando abaixo para atualizar o `docker-compose.yml` e incluir o serviço do **Spring Boot**:

- Substitua:
    - container-appspring: pelo nome do seu app
    - net-appspring: pelo nome do seu app
    - postgres: lembre de alterar os dados de conexão do app para o mesmo que informar aqui

```bash
cat <<EOF > docker-compose.yml
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
      - net-appspring

  certbot:
    image: certbot/certbot:latest
    container_name: certbot
    volumes:
      - ./nginx/certbot:/var/www/certbot
      - ./nginx/certbot-etc:/etc/letsencrypt
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do sleep 5; done'"
    networks:
      - net-appspring

    postgres:
        image: postgres:15
        networks:
          - net-appspring
        container_name: postgres
        volumes:
          - postgres-data:/var/lib/postgresql/data
        expose:
          - 5497
        ports:
          - 5497:5432
        environment:
          - POSTGRES_PASSWORD=app-senha
          - POSTGRES_USER=app-user
          - POSTGRES_DB=app_db
          - TZ=America/Sao_Paulo
        restart: unless-stopped

  container-appspring:
    image: gru.ocir.io/namespace/imagem-container-registry:latest
    container_name: container-appspring
    volumes:
      - /logs:/logs
    environment:
      - spring.profiles.active=docker
    expose:
      - 8080
    depends_on:
      - postgres
    networks:
      - net-appspring

networks:
  net-appspring:
    driver: bridge

volumes:
  postgres-data:

EOF
```

### **3. Reiniciar os Serviços**

Reinicie os containers para aplicar as alterações:

```bash
docker-compose down
docker-compose up -d
```

---

### **4. Testar o Acesso**

- Acesse o domínio `https://meudominio.com.br` no navegador.
- Verifique se o aplicativo está sendo servido corretamente.

---

## **Conclusão**

Agora você configurou com sucesso um ambiente com **Nginx**, **Certbot** e um app em **Spring Boot** utilizando **Docker Compose**. O fluxo completo incluiu:

1. Configuração inicial do Nginx para permitir a validação do Certbot.
2. Geração dos certificados SSL com Certbot.
3. Configuração final do Nginx para servir o aplicativo com HTTPS.

Este ambiente é seguro e modular, permitindo fácil manutenção e escalabilidade. Se precisar de mais ajuda, é só perguntar! 🚀
