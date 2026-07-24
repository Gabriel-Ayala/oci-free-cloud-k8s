# Database architecture and access

This platform keeps database services private to Kubernetes. PostgreSQL and
MariaDB are not exposed through OCI LoadBalancers, Contour, DNS, or public
IPs. Operators manage the database resources; users connect through the
cluster-local Service, normally by using `kubectl port-forward`.

## Architecture

```text
OCI OKE cluster
├── CloudNativePG operator (`cnpg-system`)
│   └── tools: `keycloak-postgres` (3 PostgreSQL instances)
│       ├── `keycloak-postgres-rw`  -> primary/read-write
│       ├── `keycloak-postgres-r`   -> any instance/read
│       └── `keycloak-postgres-ro`  -> replicas/read-only
└── MariaDB Operator (`mariadb-operator`)
    └── staging/production: `mariadb-mariadb-cluster` (3 Galera members)
        ├── `mariadb-mariadb-cluster-primary`   -> primary traffic
        ├── `mariadb-mariadb-cluster`            -> cluster service
        └── `mariadb-mariadb-cluster-secondary`  -> secondary traffic

Database pods
├── one 100 GiB `oci-bv` PVC per database member
├── required hostname anti-affinity: one member per worker node
├── PostgreSQL: CNPG replication and Barman Cloud backups
└── MariaDB: Galera replication and daily physical backups

Credentials
└── OCI Vault -> External Secrets -> Kubernetes Secret
```

CloudNativePG is installed as an operator baseline in tools, staging, and
production. The PostgreSQL cluster currently exists only in tools for the
Keycloak workload. MariaDB Operator and its three-member Galera cluster are
deployed in staging and production. Credentials are generated or stored in
OCI Vault and must not be committed to Git.

## Select a cluster

Use the generated kubeconfig for the target cluster. The repository normally
uses these paths; temporary paths may be used when the local kubeconfig is
read-only:

```sh
export KUBECONFIG="$PWD/terraform/.kube.tools.config"       # PostgreSQL
export KUBECONFIG="$PWD/terraform/.kube.staging.config"     # staging MariaDB
export KUBECONFIG="$PWD/terraform/.kube.production.config"  # production MariaDB

kubectl get nodes
```

## PostgreSQL: tools / Keycloak

The cluster is `keycloak-postgres` in namespace `keycloak`. It initializes the
`keycloak` database and `keycloak` owner. The generated application Secret is
`keycloak-postgres-app`; CNPG also creates TLS material in
`keycloak-postgres-ca`.

Check the cluster and services:

```sh
kubectl -n keycloak get cluster keycloak-postgres
kubectl -n keycloak get pods -l cnpg.io/cluster=keycloak-postgres -o wide
kubectl -n keycloak get svc keycloak-postgres-rw keycloak-postgres-r keycloak-postgres-ro
```

Forward the read-write service and connect with `psql`:

```sh
kubectl -n keycloak port-forward svc/keycloak-postgres-rw 15432:5432
```

In another terminal:

```sh
export PGUSER="$(kubectl -n keycloak get secret keycloak-postgres-app -o jsonpath='{.data.username}' | base64 -d)"
export PGPASSWORD="$(kubectl -n keycloak get secret keycloak-postgres-app -o jsonpath='{.data.password}' | base64 -d)"

PGPASSWORD="$PGPASSWORD" PGSSLMODE=require psql \
  --host=127.0.0.1 --port=15432 \
  --username="$PGUSER" --dbname=keycloak

unset PGUSER PGPASSWORD
```

Use `keycloak-postgres-r` or `keycloak-postgres-ro` for read-only traffic. Do
not connect directly to individual PostgreSQL pod IPs; the CNPG Services keep
primary and replica routing correct during failover.

## MariaDB: staging or production

The cluster is `mariadb-mariadb-cluster` in namespace `mariadb`. The root
password is synchronized to the `mariadb-root` Secret under the key
`root-password`.

Check the cluster and placement:

```sh
kubectl -n mariadb get mariadb mariadb-mariadb-cluster
kubectl -n mariadb get pods -o wide
kubectl -n mariadb get svc mariadb-mariadb-cluster \
  mariadb-mariadb-cluster-primary mariadb-mariadb-cluster-secondary
```

Forward the primary service:

```sh
kubectl -n mariadb port-forward svc/mariadb-mariadb-cluster-primary 13306:3306
```

In another terminal, connect with the MariaDB client:

```sh
export MYSQL_PWD="$(kubectl -n mariadb get secret mariadb-root -o jsonpath='{.data.root-password}' | base64 -d)"

MYSQL_PWD="$MYSQL_PWD" mariadb \
  --host=127.0.0.1 --port=13306 \
  --user=root --database=mysql \
  --ssl

unset MYSQL_PWD
```

The `mariadb-mariadb-cluster` Service is the general cluster endpoint;
`-primary` and `-secondary` provide explicit traffic roles. Use the primary
endpoint for writes. Do not expose these Services publicly or use pod IPs for
application configuration.

## Operational checks

```sh
# Operator and CRD health
kubectl -n cnpg-system get pods,deployments
kubectl -n mariadb-operator get pods,helmrelease

# Database health
kubectl -n keycloak get cluster keycloak-postgres
kubectl -n mariadb get mariadb mariadb-mariadb-cluster

# Storage, backups, and recent database events
kubectl -n keycloak get pvc
kubectl -n mariadb get pvc,physicalbackup
kubectl get events -A --sort-by=.lastTimestamp | tail -30
```

The expected healthy states are CNPG `Cluster in healthy state`, MariaDB
`Ready=True` / `Running`, all three database pods `Ready`, and successful
physical-backup resources. Confirm that the three database pods have three
different `kubernetes.io/hostname` values before maintenance or failover
testing.
