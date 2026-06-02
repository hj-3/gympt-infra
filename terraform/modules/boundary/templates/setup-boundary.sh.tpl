#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/boundary-setup.log | logger -t boundary-setup) 2>&1

echo "=== [1/4] System update ==="
dnf update -y

# -------------------------------------------------------
# [2/4] PostgreSQL 15 설치 및 Boundary DB 생성
# -------------------------------------------------------
echo "=== [2/4] Installing PostgreSQL 15 ==="
dnf install -y postgresql15 postgresql15-server

/usr/bin/postgresql-setup --initdb
systemctl enable postgresql
systemctl start postgresql

# pg_hba.conf: local/127.0.0.1 인증을 md5로 변경
PG_HBA="/var/lib/pgsql/data/pg_hba.conf"
sed -i 's/^local\s\+all\s\+all\s\+peer/local   all             all                                     md5/' "$PG_HBA"
sed -i 's/^host\s\+all\s\+all\s\+127\.0\.0\.1\/32\s\+ident/host    all             all             127.0.0.1\/32            md5/' "$PG_HBA"
sed -i 's/^host\s\+all\s\+all\s\+::1\/128\s\+ident/host    all             all             ::1\/128                 md5/' "$PG_HBA"

systemctl restart postgresql

sudo -u postgres psql <<SQL
CREATE USER boundary WITH PASSWORD '${db_password}';
CREATE DATABASE boundary OWNER boundary;
GRANT ALL PRIVILEGES ON DATABASE boundary TO boundary;
SQL

echo "PostgreSQL ready."

# -------------------------------------------------------
# [3/4] HashiCorp Boundary 설치
# -------------------------------------------------------
echo "=== [3/4] Installing Boundary ${boundary_version} ==="
dnf install -y dnf-plugins-core yum-utils

cat > /etc/yum.repos.d/hashicorp.repo << 'REPO'
[hashicorp]
name=HashiCorp Stable - $basearch
baseurl=https://rpm.releases.hashicorp.com/AmazonLinux/2023/$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://rpm.releases.hashicorp.com/gpg
REPO

dnf install -y boundary

useradd --system --home /etc/boundary.d --shell /bin/false boundary 2>/dev/null || true
mkdir -p /etc/boundary.d /var/log/boundary

# -------------------------------------------------------
# [4/4] Boundary 설정 및 서비스 등록
# -------------------------------------------------------
echo "=== [4/4] Configuring Boundary ==="
PUBLIC_IP=$(curl -sf http://169.254.169.254/latest/meta-data/public-ipv4)

cat > /etc/boundary.d/boundary.hcl << BOUNDARYEOF
disable_mlock = true

controller {
  name        = "${var.project_name}-${var.env}-boundary-controller"
  description = "GYMPT ${var.env} Boundary Controller"

  database {
    url = "postgresql://boundary:${db_password}@127.0.0.1/boundary?sslmode=disable"
  }
}

worker {
  name              = "${var.project_name}-${var.env}-boundary-worker"
  description       = "GYMPT ${var.env} Boundary Worker"
  public_addr       = "$PUBLIC_IP:9202"
  initial_upstreams = ["127.0.0.1:9201"]
}

listener "tcp" {
  address     = "0.0.0.0:9200"
  purpose     = "api"
  tls_disable = true
}

listener "tcp" {
  address = "0.0.0.0:9201"
  purpose = "cluster"
}

listener "tcp" {
  address = "0.0.0.0:9202"
  purpose = "proxy"
}

kms "awskms" {
  purpose    = "root"
  region     = "${aws_region}"
  kms_key_id = "${kms_root_key_id}"
}

kms "awskms" {
  purpose    = "worker-auth"
  region     = "${aws_region}"
  kms_key_id = "${kms_worker_auth_key_id}"
}

kms "awskms" {
  purpose    = "recovery"
  region     = "${aws_region}"
  kms_key_id = "${kms_recovery_key_id}"
}
BOUNDARYEOF

chown -R boundary:boundary /etc/boundary.d /var/log/boundary
chmod 640 /etc/boundary.d/boundary.hcl

# DB 초기화 (최초 1회)
echo "=== Initializing Boundary database ==="
boundary database init \
  -config=/etc/boundary.d/boundary.hcl \
  -skip-auth-method-creation=false \
  2>&1 | tee /var/log/boundary-init.log
INIT_EXIT=$${PIPESTATUS[0]}

if [ $INIT_EXIT -ne 0 ]; then
  echo "WARNING: database init returned $INIT_EXIT (may already be initialized)"
fi

# systemd 서비스
cat > /etc/systemd/system/boundary.service << 'SVCEOF'
[Unit]
Description=HashiCorp Boundary
Documentation=https://developer.hashicorp.com/boundary
Requires=network-online.target postgresql.service
After=network-online.target postgresql.service

[Service]
Type=simple
User=boundary
Group=boundary
ExecStart=/usr/bin/boundary server -config=/etc/boundary.d/boundary.hcl
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
StandardOutput=journal
StandardError=journal
SyslogIdentifier=boundary

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable boundary
systemctl start boundary

echo ""
echo "============================================"
echo " Boundary setup complete"
echo " API / UI : http://$PUBLIC_IP:9200"
echo " Init log : /var/log/boundary-init.log"
echo " Setup log: /var/log/boundary-setup.log"
echo "============================================"
