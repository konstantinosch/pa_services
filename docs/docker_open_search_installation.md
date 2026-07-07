#install docker + compose v2
sudo apt update
sudo apt install -y wget curl gnupg
sudo apt install -y docker.io docker-compose-v2
sudo systemctl enable --now docker
sudo usermod -aG docker kc
newgrp docker

#check docker
docker --version
docker compose version

#download - install open search - NATIVE INSTALL ONLY
#cd /opt
#sudo wget https://artifacts.opensearch.org/releases/bundle/opensearch/2.19.4/opensearch-2.19.4-linux-x64.tar.gz
#sudo tar -xzf opensearch-2.19.4-linux-x64.tar.gz
#sudo mv opensearch-2.19.4 opensearch

mkdir -p /opt/indexer-service/docker/opensearch
cd /opt/indexer-service/docker/opensearch
nano docker-compose.yml

############################################################
###paste this block of text baby!
services:
  opensearch:
    image: opensearchproject/opensearch:2.19.4
    container_name: opensearch
    environment:
      - discovery.type=single-node
      - plugins.security.disabled=true
      - OPENSEARCH_JAVA_OPTS=-Xms1g -Xmx1g
      - OPENSEARCH_INITIAL_ADMIN_PASSWORD=PrototypePass123!
    ports:
      - "9200:9200"
      - "9600:9600"
    volumes:
      - opensearch-data:/usr/share/opensearch/data

volumes:
  opensearch-data:

############################################################
#Start OpenSearch
docker compose up -d
docker ps

#Watch logs:
docker logs -f opensearch

#Test:
curl http://localhost:9200
#Create test index
curl -X PUT http://localhost:9200/items
#If you get resource_already_exists_exception, it just already exists.
#Index test document
curl -X PUT http://localhost:9200/items/_doc/1 \
  -H 'Content-Type: application/json' \
  -d '{
    "entity_type":"item",
    "entity_id":"1",
    "title":"First prototype item",
    "body":"This row will later become a search document",
    "category":"demo",
    "status":"open"
  }'
#Search:
curl "http://localhost:9200/items/_search?q=prototype&pretty"
  