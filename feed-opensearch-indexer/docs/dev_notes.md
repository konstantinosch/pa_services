0
##for complain vscode
##ssh-add C:\Users\chant\.ssh\id_ed25519_kc_u26
##until I find a way to autoload those ala pagent

1
##setup indexer user + project rights
sudo useradd -m -s /bin/bash indexer
##later we change what user can do with
#sudo usermod -s /usr/sbin/nologin indexer
sudo mkdir -p /opt/indexer-service
sudo chown -R indexer:indexer /opt/indexer-service

2
##dev setup
##add kc dev to indexer group
sudo usermod -aG indexer kc
##apply to current session
newgrp indexer
##write settings to group
sudo chmod -R 775 /opt/indexer-service

3
sudo -u indexer -i
cd /opt/indexer-service
python3 -m venv venv
source venv/bin/activate
pip install python-dotenv
pip install mysql-connector-python

4
##mysql setup
sudo apt update
sudo apt install -y mysql-server
mysqld --version
mysql --version
sudo systemctl enable mysql
sudo systemctl start mysql
sudo systemctl status mysql
sudo mysql
#run demo_database.sql 

5
##for dbeaver lovers...
##connect to localhost
#indexer / indexerpass / indexer_demo / classic port
#ssh tunnel to host (kc_u26) add public key - private key (no ppk)


6
##indexer in Linux:
##OS account
##runs the daemon process
##owns files/logs/services

##indexer in MySQL:
##database account
##has SQL permissions
##connects to search_prototype

7
##regarding .env
##in deployment this file somewhere else with root only access or service user access
##sudo chown root:indexer /etc/search-indexer/search-indexer.env
##sudo chmod 640 /etc/search-indexer/search-indexer.env


8
##worker_id = ποιος πήρε το job
##claim_id  = σε ποιο batch ανήκει