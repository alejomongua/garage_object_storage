# Garage S3 Storage with Docker Compose

This project sets up a Garage S3-compatible storage server with Nginx as a reverse proxy with SSL/TLS support.

## Project Structure

```
.
├── docker-compose.yml
├── config/
│   ├── garage.toml
│   └── nginx.conf
├── certs/
│   ├── privkey.pem
│   └── fullchain.pem
├── data/
│   └── garage/
│       ├── meta/
│       └── data/
└── README.md
```

## Prerequisites

- Docker and Docker Compose installed
- SSL certificates (privkey.pem and fullchain.pem) in the `certs/` folder
- OpenSSL (for generating secrets) and either envsubst or Python 3 for rendering the config template

## Setup Instructions

### 1. Provide secrets via a .env file and config template

Copy the configuration template and provide secure secrets. Use the included helper script to generate or use existing secrets and render the template:

```bash
# Make the setup script executable and run it
bash setup.sh
```

What the script does:
- Generates RPC_SECRET (hex) and tokens (base64) if missing
- Writes exported variables to `.env`
- Renders `config/garage.toml` from `config/garage.toml.tpl` using `envsubst` or Python 3
- Validates RPC_SECRET length

If you prefer manual steps:
```bash
# Copy template (or render with envsubst)
cp config/garage.toml.tpl config/garage.toml

# Generate values
RPC_SECRET=$(openssl rand -hex 32)
ADMIN_TOKEN=$(openssl rand -base64 32)
METRICS_TOKEN=$(openssl rand -base64 32)

# Write exported variables to .env
cat > .env <<EOF
export RPC_SECRET=$RPC_SECRET
export ADMIN_TOKEN=$ADMIN_TOKEN
export METRICS_TOKEN=$METRICS_TOKEN
EOF

# Render with envsubst (or use set -a trick)
envsubst < config/garage.toml.tpl > config/garage.toml
# or
set -a; . .env; set +a; envsubst < config/garage.toml.tpl > config/garage.toml
```

Ensure the generated `config/garage.toml` is ignored by git (see [.gitignore](.gitignore:1)), and keep secrets out of the repository.

Docker Compose will pick up `.env` by default; then start the services:
```bash
docker-compose up -d
```

### 2. Prepare SSL Certificates

Ensure your SSL certificates are in the `certs/` folder:
- `certs/privkey.pem` - Private key
- `certs/fullchain.pem` - Full certificate chain

### 3. Create Data Directories

Create the necessary data directories for Garage:

```bash
mkdir -p data/garage/meta data/garage/data
```

### 4. Start the Services

```bash
docker-compose up -d
```

### 5. Initialize Garage

First, check the Garage status:

```bash
docker exec -it garage /garage status
```

Note the node ID from the output, then create and apply the cluster layout. Garage requires an applied cluster layout (the "ring") before it can safely serve durable reads/writes — if no layout is applied you will see repeated warnings like "Ring not yet ready, read/writes will be lost!" in the container logs.

```bash
# Replace <node_id> with your actual node ID (you can use just the first few characters)
docker exec -it garage /garage layout assign -z dc1 -c 1G <node_id>

# Apply the layout (use version 1 for a fresh layout)
docker exec -it garage /garage layout apply --version 1
```

After applying the layout the node will be assigned partitions and Garage will schedule a full sync. Verify the result:

```bash
# check node roles and health
docker exec -it garage /garage status

# view the applied layout and staged changes
docker exec -it garage /garage layout show

# follow container logs to confirm warnings stop and sync tasks run
docker-compose logs -f garage
```

If the "Ring not yet ready" warnings persist, check that:
- `replication_factor = 1` in [`config/garage.toml`](config/garage.toml:14) for single-node deployments.
- Data directories exist and are writable (`data/garage/meta` and `data/garage/data`). Example fix:
  ```bash
  mkdir -p data/garage/{meta,data}
  chmod -R 755 data/
  ```
- Ensure Docker Compose is using the intended `config/garage.toml` (see [`docker-compose.yml`](docker-compose.yml:11)).

### 6. Create a Bucket and Access Key

```bash
# Create a bucket
docker exec -it garage /garage bucket create my-bucket

# Create an access key
docker exec -it garage /garage key create my-app-key

# Grant permissions
docker exec -it garage /garage bucket allow --read --write --owner my-bucket --key my-app-key
```

## Accessing Garage

All services are accessible only through SSL/TLS via Nginx:

- **S3 API (SSL)**: https://localhost:36443 - Main S3-compatible API
- **S3 Web (SSL)**: https://localhost:36444 - Static website hosting
- **Admin API (SSL)**: https://localhost:36445 - Administrative operations
- **K2V API (SSL)**: https://localhost:36446 - Key-Value store API
- **RPC (SSL/TLS)**: localhost:36447 - Inter-node communication (for multi-node clusters)

### About the Ports

- **Port 3900 (S3 API)**: Proxied via HTTPS on 36443
- **Port 3901 (RPC)**: Proxied via TLS on 36447 - Used for communication between Garage nodes in multi-node setups
- **Port 3902 (S3 Web)**: Proxied via HTTPS on 36444
- **Port 3903 (Admin API)**: Proxied via HTTPS on 36445
- **Port 3904 (K2V API)**: Proxied via HTTPS on 36446

**Important Security Note**: The direct Garage ports (3900-3904) are commented out in docker-compose.yml to prevent plain-text exposure. All traffic goes through Nginx with SSL/TLS encryption, making it safe for internet exposure.

For **multi-node clusters**, other Garage nodes will need to connect via the RPC port (36447 with TLS), and you'll need to configure their `rpc_public_addr` to point to this SSL endpoint.

## Using with AWS CLI

Configure AWS CLI to use Garage:

```bash
# Create ~/.awsrc file
cat > ~/.awsrc <<EOF
export AWS_ACCESS_KEY_ID=<your_key_id>
export AWS_SECRET_ACCESS_KEY=<your_secret_key>
export AWS_DEFAULT_REGION='garage'
export AWS_ENDPOINT_URL='https://localhost:36443'
EOF

# Source the configuration
source ~/.awsrc

# Test the connection (use --no-verify-ssl for self-signed certs)
aws s3 ls --no-verify-ssl
aws s3 cp test.txt s3://my-bucket/ --no-verify-ssl
```

## Useful Commands

```bash
# View logs
docker-compose logs -f

# Stop services
docker-compose down

# Restart services
docker-compose restart

# Access Garage CLI
docker exec -it garage /garage status
docker exec -it garage /garage bucket list
docker exec -it garage /garage key list

# View bucket info
docker exec -it garage /garage bucket info my-bucket
```

## Security Notes

1. **Change default secrets**: Always generate new random values for `rpc_secret`, `admin_token`, and `metrics_token`
2. **Use proper SSL certificates**: For production, use certificates from a trusted CA
3. **Firewall**: Ensure only necessary ports are exposed to the internet
4. **Backup**: The data is stored in `./data/garage/` - ensure this is backed up regularly

## Production Considerations

This setup is for a **single-node deployment** and should not be used in production as-is because:
- No data redundancy (replication_factor = 1)
- Data stored locally on one machine

For production deployments:
- Use multiple Garage nodes (minimum 3 recommended)
- Set appropriate replication factor (3 or higher)
- Use proper persistent storage
- Implement monitoring and alerting
- Use real SSL certificates from Let's Encrypt or a CA

## Troubleshooting

**Issue**: Cannot connect to Garage
- Check if containers are running: `docker-compose ps`
- Check logs: `docker-compose logs garage`

**Issue**: SSL certificate errors
- Verify certificate files exist and have correct permissions
- For self-signed certificates, use `--no-verify-ssl` flag with AWS CLI

**Issue**: Permission denied errors
- Ensure the `data/garage/meta` and `data/garage/data` directories are writable
- Check file permissions: `chmod -R 755 data/`

## Additional Resources

- [Garage Documentation](https://garagehq.deuxfleurs.fr/documentation/)
- [S3 API Compatibility](https://garagehq.deuxfleurs.fr/documentation/reference-manual/s3-compatibility/)
- [Multi-node Setup](https://garagehq.deuxfleurs.fr/documentation/cookbook/real-world/)