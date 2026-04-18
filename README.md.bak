# Dieta Milenar + SocialProof

Plataforma completa para venda de infoprodutos com área pública de conversão, checkout, área de membros, painel administrativo, módulo de revenda/afiliados e engine de Social Proof com widget embutível.

Este pacote reúne dois produtos integrados:

- **Dieta Milenar**: aplicação principal em **React + TypeScript + Vite + Express + MySQL + JWT + Stripe**.
- **SocialProof**: engine em **PHP + MySQL** para chat social proof, timelines, bots, widget embutível e painel administrativo.

---

## Visão geral do produto

O **Dieta Milenar** é um sistema completo para operação de um negócio digital baseado em produtos, planos, biblioteca de e-books, bônus e área de membros. O pacote já inclui estrutura de catálogo, importação de base SQL, landing pages, painéis por perfil e integrações de pagamento.

O **SocialProof** complementa a operação com um módulo separado, publicado em `/socialproof`, responsável por exibir prova social em formato de chat, com salas, blocos, timelines, bots, analytics e widget incorporável em landing pages.

---

## Principais destaques

### Dieta Milenar

- Landing page de vendas com seções de conversão
- Cadastro e login com JWT
- Perfis de usuário com papéis distintos
- Área do aluno com biblioteca de conteúdo
- Biblioteca hierárquica por categorias, subcategorias e e-books
- Biblioteca de bônus separada
- Produtos com módulos e capítulos
- Planos comerciais e páginas de oferta
- Checkout com suporte a **Stripe**
- Fluxo de pagamento manual/comprovante
- Gestão de revendedores/afiliados
- Comissões e solicitações de saque
- Tickets de suporte
- Upload de e-books, imagens e comprovantes
- Configurações globais do sistema
- Integração visual com widget do SocialProof
- Conteúdo com lógica de **drip/release progressivo**

### SocialProof

- Widget de chat embutível por iframe
- Painel administrativo próprio em PHP
- API REST dedicada
- Gestão de salas
- Gestão de bots
- Gestão de blocos e timelines
- Analytics de interação
- Engine de mensagens com fila global por sala
- Roteador compatível com raiz e subpasta
- Endpoint de cron/manual trigger
- Estrutura pronta para embutir em páginas externas

---

## Perfis de usuário suportados

O sistema principal trabalha com os seguintes papéis:

- **VISITANTE**
- **MEMBRO**
- **VIP**
- **REVENDA**
- **ADMIN**

Na prática, isso permite operar:

- acesso público e captura de leads
- área de membros
- área VIP
- painel de revendedores
- painel administrativo central

---

## Módulos funcionais do Dieta Milenar

### 1. Área pública e conversão

A aplicação entrega páginas públicas com foco em conversão, incluindo:

- hero section
- página de problemas
- página de depoimentos
- página de planos
- FAQs
- banner de urgência
- banner superior
- modal de cadastro
- modal de pagamento
- cookie banner
- schemas para SEO

### 2. Autenticação e usuários

- login por e-mail e senha
- registro de novos usuários
- leitura do usuário autenticado
- perfil do usuário
- atualização de perfil
- administração de usuários
- bloqueio/controle de status

### 3. Produtos e catálogo

- cadastro de produtos
- edição e exclusão de produtos
- produtos com preço, oferta e capa
- produtos com suporte a **PIX global** ou **PIX personalizado por produto**
- módulos e capítulos por produto
- ativação de **drip** por produto

### 4. Planos e vendas

- listagem de planos ativos
- listagem de planos inativos
- criação, edição e remoção de planos
- criação de pedidos
- listagem de pedidos
- pedidos pendentes de comprovante

### 5. Biblioteca de membros

- categorias
- subcategorias
- e-books
- bônus
- categorias de bônus
- itens de bônus
- ativação/inativação e exclusão permanente
- controle por ordem e drip days
- suporte a arquivos HTML e downloads

### 6. Revenda / afiliados

- solicitações de revendedor
- carteira do revendedor
- comissão por pedido
- pedidos com `affiliateId`
- atualização de chave PIX do revendedor
- solicitação de saque
- listagem de saques

### 7. Suporte

- abertura de tickets
- listagem de tickets
- mensagens por ticket
- acompanhamento pelo painel

### 8. Uploads e mídia

- upload de e-books
- upload de comprovantes
- listagem de arquivos disponíveis
- remoção de arquivos por nome
- armazenamento em `public/e-books` e `public/proofs`

### 9. Configurações globais

O painel administrativo permite centralizar configurações como:

- nome da aplicação
- logo
- vídeo principal
- chave PIX global
- tipo de chave PIX
- integração visual
- pixel
- elementos globais de checkout

---

## Módulos funcionais do SocialProof

### Painel administrativo

O módulo SocialProof possui painel próprio para:

- salas
- bots
- blocos
- timeline
- analytics
- configurações
- execução manual do motor

### API REST

O módulo inclui API para:

- feed público do chat
- leitura de sala por slug
- tracking
- CRUD administrativo de entidades
- analytics
- cron/manual trigger
- health check

### Engine de execução

O engine processa mensagens por sala com:

- paralelismo de blocos
- fila global por room
- priorização de respostas
- publicação gradual de mensagens

### Widget embutível

Pode ser utilizado em qualquer página externa via iframe, inclusive na landing principal do Dieta Milenar.

Exemplo:

```html
<iframe
  src="https://seudominio.com/socialproof/widget/index.php?room=seu-slug"
  width="400"
  height="600"
  frameborder="0">
</iframe>
```

---

## Stack técnica

### Aplicação principal

- React
- TypeScript
- Vite
- Express
- MySQL (`mysql2`)
- JWT
- Stripe
- Multer
- Tailwind CSS
- PM2
- Nginx

### SocialProof

- PHP
- PDO MySQL
- Nginx + PHP-FPM
- Widget em PHP
- API REST própria
- execução por cron/manual trigger

### Servidor alvo

Ambiente recomendado para este pacote:

- **Ubuntu 22.04 LTS**
- acesso root ou sudo
- Nginx
- MariaDB/MySQL
- PHP-FPM
- Node.js 20+
- PM2

> O instalador atual informa compatibilidade com **Ubuntu 20.04+ / Debian 11+**, mas o menu operacional foi estruturado pensando em **Ubuntu 22.04+**.

---

## Estrutura de banco de dados

### Banco principal

A base principal do Dieta Milenar trabalha com tabelas como:

- users
- user_profiles
- plans
- orders
- commissions
- withdrawals
- products
- product_modules
- product_chapters
- categories
- subcategories
- ebooks
- bonuses
- bonus_categories
- bonus_items
- notifications
- reseller_requests
- tickets
- ticket_messages
- timelines
- timeline_blocks
- bots
- affiliate_clicks
- global_settings

### Banco do SocialProof

O instalador cria um banco dedicado chamado:

- `socialproof`

Esse banco recebe o SQL próprio do módulo SocialProof durante a instalação.

---

## Conteúdo incluso no pacote

Arquivos principais encontrados no pacote atual:

- `Projeto.zip`
- `install.sh`
- `install.zip`
- `init.sh`
- `menuFULL.sh`
- `unistall.sh`
- `install_original_backup.sh`

### O que cada arquivo faz

#### `Projeto.zip`
Pacote principal da aplicação e do módulo SocialProof.

#### `install.sh`
Instalador principal do sistema. Faz:

- extração do projeto
- instalação de dependências do sistema
- instalação do Node.js 20
- configuração do MariaDB/MySQL
- instalação opcional do phpMyAdmin
- deploy do Dieta Milenar
- deploy do SocialProof
- geração do `.env`
- build do frontend
- preparo do backend em Node
- importação dos bancos SQL
- configuração de permissões
- criação do comando `start`
- configuração do PM2
- configuração do Nginx
- SSL opcional com Certbot

#### `init.sh`
Script preparatório. Faz:

- ajuste de permissões dos arquivos clonados
- ownership do pacote para `ubuntu`
- concessão de `sudo NOPASSWD:ALL` ao usuário `ubuntu`
- execução automática do `install.sh`

#### `menuFULL.sh`
Menu operacional unificado para administração da stack, incluindo:

- fix de permissões
- serviços
- logs
- banco de dados
- diagnóstico
- alternância de modo DEV/PROD

#### `unistall.sh`
Script de rollback seguro da stack. Remove apenas o que pertence ao pacote, preservando por padrão os componentes compartilhados do sistema.

#### `bashrc`
Arquivo auxiliar de ambiente do autor. **Não é necessário para deploy do produto**.

---

## Requisitos do servidor

Antes da instalação, garanta:

- acesso root ou sudo
- conexão com internet
- IPv4 público ou domínio apontado
- portas 80 e 443 liberadas
- usuário `ubuntu` existente, caso você queira usar `init.sh`
- os arquivos do pacote no mesmo diretório

---

## Instalação rápida

### Opção 1 — instalação completa com preparação automática

Use esta opção quando quiser preparar permissões do pacote e dar acesso administrativo total ao usuário `ubuntu` antes da instalação:

```bash
sudo chmod +x init.sh install.sh menuFULL.sh unistall.sh
sudo bash init.sh
```

### Opção 2 — instalação direta

Use esta opção quando a máquina já estiver preparada:

```bash
sudo chmod +x install.sh menuFULL.sh unistall.sh
sudo bash install.sh
```

---

## Fluxo da instalação

Durante a execução do `install.sh`, o sistema pede:

1. se será usado domínio ou IP
2. domínio e e-mail para SSL, se aplicável
3. nome do banco principal
4. usuário do banco
5. senha do banco
6. Stripe secret key
7. JWT secret
8. instalação opcional do phpMyAdmin

Ao final, o instalador entrega:

- app principal no Nginx
- SocialProof em `/socialproof`
- phpMyAdmin em `/phpmyadmin` se habilitado
- PM2 configurado
- comando `start` configurado

---

## URLs esperadas após instalação

### Sem domínio

- `http://IP_DO_SERVIDOR/`
- `http://IP_DO_SERVIDOR/socialproof/`
- `http://IP_DO_SERVIDOR/phpmyadmin/` (se habilitado)

### Com domínio

- `http://seudominio.com/` ou `https://seudominio.com/`
- `http://seudominio.com/socialproof/` ou `https://seudominio.com/socialproof/`
- `http://seudominio.com/phpmyadmin/` ou `https://seudominio.com/phpmyadmin/`

---

## Operação do sistema após instalado

O instalador cria o wrapper:

```bash
start
```

Esse comando abre o menu operacional instalado em:

```bash
/var/www/dieta-milenar/menu.sh
```

### O menu operacional inclui

- **Fix**
- **Serviços**
- **Logs**
- **Banco de Dados**
- **Diagnóstico**
- **MODE (DEV / PROD)**

### Exemplos de operação

```bash
start
```

```bash
sudo bash /var/www/dieta-milenar/menu.sh
```

---

## Desinstalação / rollback

O pacote inclui o script:

```bash
unistall.sh
```

> O nome do arquivo está exatamente assim no pacote: `unistall.sh`.

### Simulação segura

```bash
sudo bash unistall.sh --dry-run
```

### Rollback padrão

```bash
sudo bash unistall.sh
```

### Rollback agressivo

```bash
sudo bash unistall.sh --purge-shared-packages --remove-swap --delete-certs
```

---

## Estrutura lógica do projeto

### Dieta Milenar

```text
DietaMilenar/
├── server.ts
├── package.json
├── src/
├── public/
├── DataBaseFULL/
├── .env.example
└── assets/
```

### SocialProof

```text
SocialProof/
├── index.php
├── api/
├── admin/
├── widget/
├── includes/
├── cron.php
└── DataBaseFULL/
```

---

## Personalização

Você pode adaptar o produto para outros nichos sem alterar a arquitetura principal.

Áreas mais simples de personalizar:

- nome da marca
- cores
- logo
- vídeos
- páginas públicas
- planos
- produtos
- e-books
- bônus
- mensagens do SocialProof
- widget de prova social

---

## Serviços externos / contas necessárias

Dependendo do seu uso, você pode precisar de:

- conta Stripe
- domínio próprio
- DNS configurado
- e-mail válido para emissão SSL
- cron ativo para SocialProof, se quiser processamento programado

---

## Observações importantes para produção

Antes de publicar em ambiente real, é recomendável:

- revisar todas as credenciais
- trocar segredos e chaves
- revisar usuários seed importados pelo SQL
- revisar textos comerciais e mídias
- revisar permissões de servidor
- revisar exposição de phpMyAdmin
- revisar os dados de exemplo presentes no banco

---

## Indicado para

Este pacote é indicado para:

- venda de infoprodutos
- bibliotecas digitais e áreas de membros
- operações com revenda/afiliados
- funis com prova social embutida
- projetos que precisam unir **landing page + checkout + members area + social proof** em uma única stack

---

## Resumo comercial

**Dieta Milenar + SocialProof** é um pacote completo para operações digitais que precisam de:

- aquisição
- conversão
- checkout
- área de membros
- revenda
- suporte
- biblioteca de conteúdo
- prova social em tempo real
- deploy em VPS própria

É uma base pronta para comercialização, customização e operação sob domínio próprio, com instalador em shell, painel administrativo web, área de membros e módulo de social proof integrado.
