# Load Balancer
## Prerequisite  

### Networks
- websites

```
docker network create --attachable --driver=DRIVER_NAME websites
```

## Run Load Balancer

```
curl -s https://raw.githubusercontent.com/scbd/bioland-infra/master/services/load-balancer-compose.yml | docker-compose -f - -p load-balancer up -d
```
