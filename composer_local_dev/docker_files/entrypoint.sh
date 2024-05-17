#!/bin/sh"

# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -xe

sudo chown airflow:airflow airflow

mkdir -p ${AIRFLOW__CORE__DAGS_FOLDER}
mkdir -p ${AIRFLOW__CORE__PLUGINS_FOLDER}

# That file exists in Composer < 1.19.2 and is responsible for linking name
# `python` to python3 exec, in Composer >= 1.19.2 name `python` is already
# linked to python3 and file no longer exist.
if [ -f /var/local/setup_python_command.sh ]; then
    /var/local/setup_python_command.sh
fi

pip3 install --upgrade -r composer_requirements.txt
pip3 check

# We have no control on the Dockerfile, so the patch code has to be included in this entrypoint.sh file
read -r -d '' PATCH << EOL
--- /opt/python3.8/lib/python3.8/site-packages/dbt/include/global_project/macros/adapters/columns.sql
+++ /opt/python3.8/lib/python3.8/site-packages/dbt/include/global_project/macros/adapters/columns.sql
@@ -114,11 +114,11 @@
      alter {{ relation.type }} {{ relation }}
 
             {% for column in add_columns %}
-               add column {{ column.name }} {{ column.data_type }}{{ ',' if not loop.last }}
+               add column {{ adapter.quote(column.name) }} {{ column.data_type }}{{ ',' if not loop.last }}
             {% endfor %}{{ ',' if add_columns and remove_columns }}
 
             {% for column in remove_columns %}
-                drop column {{ column.name }}{{ ',' if not loop.last }}
+                drop column {{ adapter.quote(column.name) }}{{ ',' if not loop.last }}
             {% endfor %}
 
   {%- endset -%}
EOL

cd / && patch -p0 < $PATCH

export PATH="$PATH:/home/airflow/docker_files/bin"

sudo apt-get update
sudo apt install netcat -y
echo "Trying to ping host to ensure connection works"
ping host.docker.internal -c 5 || echo "Ping failed"
echo "Acessing the SSH port"
nc -z -v -w5 host.docker.internal 22 || echo "SSH failed"
echo "Acessing the MySQL port"
nc -z -v -w5 host.docker.internal 3306 || echo "MySQL failed"

airflow db init

# Allow non-authenticated access to UI for Airflow 2.*
if ! grep -Fxq "AUTH_ROLE_PUBLIC = 'Admin'" /home/airflow/airflow/webserver_config.py; then
  echo "AUTH_ROLE_PUBLIC = 'Admin'" >> /home/airflow/airflow/webserver_config.py
fi

airflow scheduler &
exec airflow webserver
