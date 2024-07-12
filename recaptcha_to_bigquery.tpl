___INFO___

{
  "type": "TAG",
  "id": "cvt_temp_public_id",
  "version": 1,
  "securityGroups": [],
  "displayName": "reCAPTCHA to BigQuery",
  "brand": {
    "id": "brand_dummy",
    "displayName": ""
  },
  "description": "Used to save reCAPTCHA assessment to BigQuery with GA4 Client ID.",
  "containerContexts": [
    "SERVER"
  ]
}


___TEMPLATE_PARAMETERS___

[
  {
    "type": "TEXT",
    "name": "assessment",
    "displayName": "reCAPTCHA Assessment",
    "simpleValueType": true
  },
  {
    "type": "GROUP",
    "name": "bigQuery",
    "displayName": "BigQuery",
    "groupStyle": "NO_ZIPPY",
    "subParams": [
      {
        "type": "TEXT",
        "name": "bigQueryCloudProjectId",
        "displayName": "Cloud Project ID",
        "simpleValueType": true
      },
      {
        "type": "TEXT",
        "name": "bigQueryDatasetId",
        "displayName": "Dataset ID",
        "simpleValueType": true
      },
      {
        "type": "TEXT",
        "name": "bigQueryTableId",
        "displayName": "Table ID",
        "simpleValueType": true
      }
    ]
  }
]


___SANDBOXED_JS_FOR_SERVER___

/**
 * Copyright 2024 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

const promise = require('Promise').create;
const bigQueryInsert = require('BigQuery').insert;
const logToConsole = require('logToConsole');
const getType = require('getType');

// request and response specific methods.
const request = {
  isAnalytics: require('isRequestMpv2'),
  eventData: require('getAllEventData')
};

const response = {
  success: data.gtmOnSuccess,
  failure: (error) => {
    logToConsole('Error occurred:', error);
    data.gtmOnFailure();
  }
};

if (request.isAnalytics()) {
  if (getType(data.assessment) === 'object') {
    const eventData = request.eventData();
    outputToBigQuery(eventData, data.assessment)
      .then(response.success)
      .catch(response.failure);
  } else {
    logToConsole('Error occurred: assessment provided was not valid and could not be stored.');
  }
}

/**
 * Outputs necessary data from the assessment to the BigQuery table specified in the configuration.
 *
 * @param {Object} eventData Contains all data pulled from the request that came into sGTM.
 * @param {string} eventData.client_id The pseudo identifier associated with a unique user.
 * @param {Object} assessment
 * @param {Object} assessment.tokenProperties
 * @param {string} assessment.tokenProperties.createTime The time the token was created.
 * @param {boolean} assessment.tokenProperties.valid Whether or not the token is considered valid.
 * @param {string} assessment.tokenProperties.invalidReason Why the token is considered invalid.
 * @param {Object} assessment.riskAnalysis
 * @param {number} assessment.riskAnalysis.score The score attributed to the token (0 being worst and 1 being best).
 * @param {string[]} assessment.riskAnalysis.reasons The reasons provided for why the score is what it is.
 * @param {string[]} assessment.riskAnalysis.extendedVerdictReasons Additional details on why the score is what it is.
 * @returns {Promise<Object>} The reCAPTCHA assessment containing score, token validity, and reasons for score.
 */
function outputToBigQuery(eventData, assessment) {
  const connectionInfo = {
    projectId: data.bigQueryCloudProjectId,
    datasetId: data.bigQueryDatasetId,
    tableId: data.bigQueryTableId
  };

  const row = {
    client_id: eventData.client_id,
    risk_analysis: {
      score: assessment.riskAnalysis.score,
      reasons: assessment.riskAnalysis.reasons,
      extended_verdict_reasons: assessment.riskAnalysis.extendedVerdictReasons
    },
    token_properties: {
      valid: assessment.tokenProperties.valid,
      invalid_reason: assessment.tokenProperties.invalidReason
    }
  };

  // only attach timestamp if the token create time is available and otherwise
  // let the table defaults set the current time.
  if (assessment.tokenProperties.createTime) {
    row.timestamp = assessment.tokenProperties.createTime;
  }

  return promise((resolve, reject) => {
    bigQueryInsert(connectionInfo, [row])
      .then(resolve)
      .catch(reject);
  });
}


___SERVER_PERMISSIONS___

[
  {
    "instance": {
      "key": {
        "publicId": "logging",
        "versionId": "1"
      },
      "param": [
        {
          "key": "environments",
          "value": {
            "type": 1,
            "string": "debug"
          }
        }
      ]
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "read_event_data",
        "versionId": "1"
      },
      "param": [
        {
          "key": "eventDataAccess",
          "value": {
            "type": 1,
            "string": "any"
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "access_bigquery",
        "versionId": "1"
      },
      "param": [
        {
          "key": "allowedTables",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "projectId"
                  },
                  {
                    "type": 1,
                    "string": "datasetId"
                  },
                  {
                    "type": 1,
                    "string": "tableId"
                  },
                  {
                    "type": 1,
                    "string": "operation"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "*"
                  },
                  {
                    "type": 1,
                    "string": "*"
                  },
                  {
                    "type": 1,
                    "string": "*"
                  },
                  {
                    "type": 1,
                    "string": "write"
                  }
                ]
              }
            ]
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  }
]


___TESTS___

scenarios: []


___NOTES___

Created on 3/25/2024, 3:18:43 PM


