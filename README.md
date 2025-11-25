# Service - Dolibarr

This repository contains Docker configuration for running Dolibarr, an open-source ERP and CRM system. Dolibarr is used here as the ERP CRM for development work.

## 🏗️ Architecture

The setup includes:
- **Dolibarr Web Application**: Custom Docker image based on Dolibarr 21 with Apache configuration for serving under `/crm` path.
- **MariaDB Database**: Persistent database storage.
- **Traefik Integration**: Reverse proxy configuration with SSL termination.

## 📋 Prerequisites

- Docker
- Docker Compose
- Make (for using the Makefile commands)

## 🚀 Installation

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd dolibarr
   ```

2. Configure environment variables in `.env` file (see Configuration section).

3. Ensure the external network `private` exists (used by Traefik):
   ```bash
   docker network create private
   ```

## ⚙️ Configuration

Environment variables are defined in the `.env` file:

- `DOLI_TAG`: Dolibarr version tag (default: 21)
- `DOLI_PORT`: Port for local access (default: 8083)
- Database settings: `MYSQL_DATABASE`, `MYSQL_ROOT_PASSWORD`
- Dolibarr settings: `DOLI_DB_*`, `DOLI_ADMIN_*`, etc.
- Data directories: `DOLI_DATA_DOCUMENTS`, `DOLI_DATA_CUSTOM`

**Important**: Update paths in `DOLI_DATA_DOCUMENTS` and `DOLI_DATA_CUSTOM` to match your system's data directories.

## 🛠️ Usage

This project uses Docker Compose with a Makefile for simplified commands.

### Available Commands

```bash
# Build and start services
make up

# Stop services
make stop

# Start stopped services
make start

# Restart services
make restart

# Stop and remove services
make down

# View logs
make logs

# Update services (pull latest images and restart)
make update

# Pull latest images
make pull
```

### Database Management

```bash
# Restore database from SQL file
make db/restore DB_DUMP=path/to/dump.sql DB_PASSWORD=your_password
```

### Accessing Dolibarr

Once running, access Dolibarr at: `https://broska.hd.free.fr/crm`

Default admin credentials:
- Username: `root`
- Password: `root`

## 📁 Project Structure

```
dolibarr/
├── docker-compose.yml    # Docker Compose configuration
├── Dockerfile           # Custom Dolibarr image
├── Makefile            # Build and management commands
├── .env                # Environment variables
├── apache-config/      # Apache configuration
│   └── dolibarr-crm.conf
├── README.md           # This file
└── TODO.md             # Development tasks
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

Copyright (c) Xavier Beheydt. All rights reserved.
