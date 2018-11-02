# Load Balancer
## Prerequisite  

### Networks
- webgateway

```
docker network create --attachable --driver=DRIVER_NAME webgateway
```

## Run Load Balancer

```
curl -s https://raw.githubusercontent.com/scbd/bioland-infra/master/services/load-balancer-compose.yml | docker-compose -f - -p load-balancer up -d
```
