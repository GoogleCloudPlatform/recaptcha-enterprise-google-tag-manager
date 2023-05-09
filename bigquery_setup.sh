#!/bin/bash
###########################################################################
#
#  Copyright 2023 Google Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      https://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

echo "-------- BigQuery Setup ---------------------"
echo "Enabling BigQuery API..."
gcloud services enable bigquery.googleapis.com --async

read -p "Please enter your Google Cloud project ID: " project_id
read -p "Please enter a new BigQuery dataset name (cannot include spaces): " dataset_id
read -p "Please enter a new BigQuery table name (cannot include spaces): " table_id
read -p "Please enter the service account (email address) associated to your sGTM server: " service_account

echo "Creating BigQuery dataset..."
bq mk -d $project_id:$dataset_id

echo "Creating BigQuery table..."
bq mk -t --time_partitioning_type=DAY \
	--schema=./bigquery_schema.json \
	$project_id:$dataset_id.$table_id

echo "Adding necessary permissions..."
bq add-iam-policy-binding \
  --member=user:$service_account \
  --role=roles/bigquery.dataViewer \
  $project_id:$dataset_id

bq add-iam-policy-binding \
  --member=user:$service_account \
  --role=roles/bigquery.dataEditor \
  $project_id:$dataset_id.$table_id

echo "-------- Complete ---------------------------
Use the following when configuring the server container tag in Google Tag Manager (GTM):
- Project ID: $project_id
- Dataset ID: $dataset_id
- Table ID: $table_id
---------------------------------------------"