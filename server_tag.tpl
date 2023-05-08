___INFO___

{
  "type": "TAG",
  "id": "cvt_temp_public_id",
  "version": 1,
  "securityGroups": [],
  "displayName": "reCAPTCHA",
  "brand": {
    "id": "brand_dummy",
    "displayName": ""
  },
  "description": "Handle parsing, interpreting (getting a score), and storing the score for a given reCAPTCHA token.",
  "containerContexts": [
    "SERVER"
  ]
}


___TEMPLATE_PARAMETERS___

[
  {
    "type": "SELECT",
    "name": "version",
    "displayName": "Version",
    "selectItems": [
      {
        "value": "v3",
        "displayValue": "v3"
      },
      {
        "value": "enterprise",
        "displayValue": "Enterprise"
      }
    ],
    "simpleValueType": true
  },
  {
    "type": "TEXT",
    "name": "secretKey",
    "displayName": "Secret Key",
    "simpleValueType": true,
    "enablingConditions": [
      {
        "paramName": "version",
        "paramValue": "v3",
        "type": "EQUALS"
      }
    ]
  },
  {
    "type": "TEXT",
    "name": "cloudProjectId",
    "displayName": "Cloud Project ID",
    "simpleValueType": true,
    "enablingConditions": [
      {
        "paramName": "version",
        "paramValue": "enterprise",
        "type": "EQUALS"
      }
    ]
  },
  {
    "type": "TEXT",
    "name": "apiKey",
    "displayName": "Enterprise API Key",
    "simpleValueType": true,
    "enablingConditions": [
      {
        "paramName": "version",
        "paramValue": "enterprise",
        "type": "EQUALS"
      }
    ]
  },
  {
    "type": "TEXT",
    "name": "siteKey",
    "displayName": "Enterprise Key ID",
    "simpleValueType": true,
    "enablingConditions": [
      {
        "paramName": "version",
        "paramValue": "enterprise",
        "type": "EQUALS"
      }
    ]
  },
  {
    "type": "CHECKBOX",
    "name": "attachToEventData",
    "checkboxText": "Attach Score to Event Data",
    "simpleValueType": true
  },
  {
    "type": "CHECKBOX",
    "name": "outputToBigQuery",
    "checkboxText": "Output Score to BigQuery",
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
    ],
    "enablingConditions": [
      {
        "paramName": "outputToBigQuery",
        "paramValue": true,
        "type": "EQUALS"
      }
    ]
  },
  {
    "type": "CHECKBOX",
    "name": "loggingEnabled",
    "checkboxText": "Enable Logging",
    "simpleValueType": true
  }
]


___SANDBOXED_JS_FOR_SERVER___

/**
 * Copyright 2023 Google LLC
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

// capture start-time very first to ensure accurate performance checks.
const timestamp = require('getTimestampMillis');
const startTime = timestamp();

// request and response specific methods.
const request = {
  isAnalytics: require('isRequestMpv2'),
  eventData: require('getAllEventData')
};

const response = {
  success: data.gtmOnSuccess,
  failure: (error) => {
    log('Error occurred:', error);
    data.gtmOnFailure();
  }
};

// utility classes/methods.
const runContainer = require('runContainer');
const logToConsole = require('logToConsole');
const sendHttpRequest = require('sendHttpRequest');
const promise = require('Promise').create;
const deleteProperty = require('Object').delete;
const encodeUriComponent = require('encodeUriComponent');
const json = require('JSON');
let bigQueryInsert = require('BigQuery').insert;

// globals
const siteVerifyUrl = 'https://www.google.com/recaptcha/api/siteverify';
const enterpriseApiUrl = 'https://recaptchaenterprise.googleapis.com/v1';

if (request.isAnalytics()) {
  const eventData = request.eventData();
  if (eventData.recaptcha) {
    log('Processing reCAPTCHA...');
    getAssessment(eventData)
      .then(assessment => {
        processAssessment(eventData, assessment)
          .then(response.success)
          .catch(response.failure);
      })
      .catch(response.failure);
  }
} else {
  response.success();
}

/**
 * Gets the assessment (score, validity, etc) by providing the reCAPTCHA data to the appropriate endpoint.
 *
 * @param {Object} eventData Contains all data pulled from the request that came into sGTM.
 * @param {string} eventData.recaptcha The reCAPTCHA data JSON string that contains token and action.
 * @returns {Promise<Object>} The reCAPTCHA assessment containing score, token validity, and reasons for score.
 */
function getAssessment(eventData) {
  return promise((resolve, reject) => {
    const recaptcha = json.parse(eventData.recaptcha);

    switch (data.version) {
      case 'v3':
        getAssessmentFromSiteVerify(eventData, recaptcha)
          .then(resolve)
          .catch(reject);
        break;

      case 'enterprise':
        getAssessmentFromEnterpriseAPI(eventData, recaptcha)
          .then(resolve)
          .catch(reject);
        break;
    }
  });
}

/**
 * Calls the reCAPTCHA API site verify endpoint using the provided token to acquire an assessment.
 * This includes a score and token properties (is the token valid, when was it created, what action is associated, etc).
 *
 * @param {Object} eventData Contains all data pulled from the request that came into sGTM.
 * @param {string} eventData.ip_override The IP address associated with the request.
 * @param {Object} recaptcha The reCAPTCHA object that contains token and action.
 * @param {string} recaptcha.token The encrypted token containing necessary details required to generate a score.
 * @param {string} recaptcha.action The action provided to reCAPTCHA at the time the token was generated.
 * @returns {Promise<Object>} The reCAPTCHA assessment containing score, token validity, and reasons for score.
 */
function getAssessmentFromSiteVerify(eventData, recaptcha) {
  return promise((resolve, reject) => {
    const urlParams = buildQueryString({
      secret: data.secretKey,
      response: recaptcha.token,
      remoteip: eventData.ip_override
    });

    // the site verify endpoint requires a POST request with GET parameters.
    sendHttpRequest(siteVerifyUrl + '?' + urlParams, {
      method: 'POST',
      timeout: 5000
    })
    .then(response => {
      log(response.statusCode, response.body);
      if (response.statusCode === 200) {
        const assessment = json.parse(response.body);
        if (assessment['error-codes']) {
          log(assessment['error-codes']);
        }
        resolve({
          riskAnalysis: {
            score: assessment.score,
            reasons: [],
            extendedVerdictReasons: []
          },
          tokenProperties: {
            valid: assessment.action === recaptcha.action && assessment.success,
            invalidReason: '',
            createTime: assessment.challenge_ts,
            hostname: assessment.hostname,
            action: assessment.action
          }
        });
      } else {
        reject(response.body);
      }
    })
    .catch(reject);
  });
}

/**
 * Calls the reCAPTCHA Enterprise API create assessment endpoint using the provided token to acquire an assessment.
 * This includes a score and token properties (is the token valid, when was it created, what action is associated, etc).
 *
 * @param {Object} eventData Contains all data pulled from the request that came into sGTM.
 * @param {string} eventData.ip_override The IP address associated with the request.
 * @param {string} eventData.user_agent The user agent (usually browser details) associated with the request.
 * @param {Object} recaptcha
 * @param {string} recaptcha.token The encrypted token containing necessary details required to generate a score.
 * @param {string} recaptcha.action The action provided to reCAPTCHA at the time the token was generated.
 * @returns {Promise<Object>} The reCAPTCHA assessment containing score, token validity, and reasons for score.
 */
function getAssessmentFromEnterpriseAPI(eventData, recaptcha) {
  return promise((resolve, reject) => {
    const url = enterpriseApiUrl + '/projects/' + data.cloudProjectId + '/assessments?key=' + data.apiKey;
    const body = json.stringify({
      event: {
        token: recaptcha.token,
        siteKey: data.siteKey,
        expectedAction: recaptcha.action,
        userIpAddress: eventData.ip_override,
        userAgent: eventData.user_agent
      }
    });

    sendHttpRequest(url, {
      headers: {
        'Content-Type': 'application/json; charset=utf-8'
      },
      method: 'POST',
      timeout: 5000
    }, body)
    .then(response => {
      if (response.statusCode === 200) {
        const assessment = json.parse(response.body);
        const actionMatches = assessment.tokenProperties.action === assessment.event.expectedAction;
        assessment.tokenProperties.valid = actionMatches && assessment.tokenProperties.valid;
        resolve(assessment);
      } else {
        reject(response.body);
      }
    })
    .catch(reject);
  });
}

/**
 * Outputs necessary data from the assessment to the configured places.
 *
 * @param {Object} eventData Contains all data pulled from the request that came into sGTM.
 * @param {Object} assessment The reCAPTCHA assessment containing score, token validity, and reasons for score.
 */
function processAssessment(eventData, assessment) {
  return promise((resolve, reject) => {
    if (data.attachToEventData) {
      sendToTags(eventData, assessment);
    }

    if (data.outputToBigQuery) {
      outputToBigQuery(eventData, assessment)
        .then(resolve)
        .catch(reject);
    } else {
      resolve();
    }
  });
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
    projectId: data.cloudProjectId,
    datasetId: data.bigQueryDatasetId,
    tableId: data.bigQueryTableId
  };

  return promise((resolve, reject) => {
    const row = {
      timestamp: assessment.tokenProperties.createTime,
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

    // TODO: when it's possible to mock BigQuery.insert, update tests and remove this
    // and change bigQueryInsert at top to a constant.
    if (data.testing) {
      bigQueryInsert = data.bigQueryInsertMock;
    }

    bigQueryInsert(connectionInfo, [row])
      .then(resolve)
      .catch(reject);
  });
}

/**
 * Removes raw reCAPTCHA data, attaches necessary data from the assessment to the event data object,
 * and runs the container again which calls all the tags with this new event data.
 *
 * @param {Object} eventData Contains all data pulled from the request that came into sGTM.
 * @param {Object} assessment
 * @param {Object} assessment.riskAnalysis
 * @param {number} assessment.riskAnalysis.score The score attributed to the token (0 being worst and 1 being best).
 * @param {Object} assessment.tokenProperties
 * @param {boolean} assessment.tokenProperties.valid Whether or not the token is considered valid.
 */
function sendToTags(eventData, assessment) {
  deleteProperty(eventData, 'recaptcha');

  eventData.recaptcha_score = assessment.riskAnalysis.score;
  eventData.recaptcha_valid = assessment.tokenProperties.valid;

  log('Sending updated event data to tags...');
  runContainer(eventData);
}

/**
 * Takes an object and encodes each key and value pair returning an encoded url query string.
 *
 * @param {Object} data
 * @returns {string}
 */
function buildQueryString(data) {
  let encoded = [];
  for (const key in data) {
    const value = data[key];
    encoded.push(encodeUriComponent(key) + '=' + encodeUriComponent(value));
  }
  return encoded.join('&');
}

/**
 * Logs all parameters to the console for troubleshooting purposes.
 * Only logs if logging is enabled via the client configuration.
 * Prepends the client name to all log entries.
 *
 * @param {...mixed}
 */
function log() {
  if (data.loggingEnabled) {
    const starter = '[reCAPTCHA Tag]' + ' [' + (timestamp() - startTime) + 'ms]';
    // no spread operator is available in sandboxed JS.
    switch (arguments.length) {
      case 1:
        logToConsole(starter, arguments[0]);
        break;
      case 2:
        logToConsole(starter, arguments[0], arguments[1]);
        break;
      case 3:
        logToConsole(starter, arguments[0], arguments[1], arguments[2]);
        break;
      case 4:
        logToConsole(starter, arguments[0], arguments[1], arguments[2], arguments[3]);
        break;
      case 5:
        logToConsole(starter, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4]);
        break;
    }
  }
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
    "clientAnnotations": {
      "isEditedByUser": true
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
        "publicId": "run_container",
        "versionId": "1"
      },
      "param": []
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "send_http",
        "versionId": "1"
      },
      "param": [
        {
          "key": "allowedUrls",
          "value": {
            "type": 1,
            "string": "specific"
          }
        },
        {
          "key": "urls",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 1,
                "string": "https://www.google.com/recaptcha/api/siteverify*"
              },
              {
                "type": 1,
                "string": "https://recaptchaenterprise.googleapis.com/v1*"
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
                    "string": "dev-playground-365120"
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

scenarios:
- name: Enterprise - Success - Output to BigQuery Only
  code: "enterpriseMockData.outputToBigQuery = true;\nconst assessment = enterpriseAssessment;\n\
    \nlet params = {};\n// replace with actual mock when it's possible to mock BigQuery.insert.\n\
    enterpriseMockData.bigQueryInsertMock = (connectionInfo, rows) => {\n  params.connectionInfo\
    \ = connectionInfo;\n  params.rows = rows;\n  \n  return promise(resolve => resolve());\n\
    };\n\n// run the template code.\nrunCode(enterpriseMockData);\n\n// assertions\
    \ need to deferred due to async behaviors (promises).\ndefer(() => {\n  assertThat(params.connectionInfo).isEqualTo({\n\
    \    projectId: enterpriseMockData.cloudProjectId,\n    datasetId: enterpriseMockData.bigQueryDatasetId,\n\
    \    tableId: enterpriseMockData.bigQueryTableId\n  });\n  \n  assertThat(params.rows).isEqualTo([{\n\
    \    timestamp: assessment.tokenProperties.createTime,\n    client_id: 'test-client-id',\n\
    \    risk_analysis: {\n      score: assessment.riskAnalysis.score,\n      reasons:\
    \ assessment.riskAnalysis.reasons,\n      extended_verdict_reasons: assessment.riskAnalysis.extendedVerdictReasons\n\
    \    },\n    token_properties: {\n      valid: assessment.tokenProperties.valid,\n\
    \      invalid_reason: assessment.tokenProperties.invalidReason\n    }\n  }]);\n\
    \  \n  assertApi('runContainer').wasNotCalled();\n  assertApi('gtmOnSuccess').wasCalled();\n\
    });"
- name: v3 - Success - Output to BigQuery Only
  code: "v3MockData.outputToBigQuery = true;\nconst assessment = v3Assessment;\n\n\
    let params = {};\n// replace with actual mock when it's possible to mock BigQuery.insert.\n\
    v3MockData.bigQueryInsertMock = (connectionInfo, rows) => {\n  params.connectionInfo\
    \ = connectionInfo;\n  params.rows = rows;\n  \n  return promise(resolve => resolve());\n\
    };\n\n// run the template code.\nrunCode(v3MockData);\n\n// assertions need to\
    \ deferred due to async behaviors (promises).\ndefer(() => {\n  assertThat(params.connectionInfo).isEqualTo({\n\
    \    projectId: v3MockData.cloudProjectId,\n    datasetId: v3MockData.bigQueryDatasetId,\n\
    \    tableId: v3MockData.bigQueryTableId\n  });\n  \n  assertThat(params.rows).isEqualTo([{\n\
    \    timestamp: assessment.challenge_ts,\n    client_id: 'test-client-id',\n \
    \   risk_analysis: {\n      score: assessment.score,\n      reasons: [],\n   \
    \   extended_verdict_reasons: []\n    },\n    token_properties: {\n      valid:\
    \ assessment.success,\n      invalid_reason: ''\n    }\n  }]);\n  \n  assertApi('runContainer').wasNotCalled();\n\
    \  assertApi('gtmOnSuccess').wasCalled();\n});"
- name: Enterprise - Failure - Output to BigQuery Only
  code: "enterpriseMockData.outputToBigQuery = true;\nconst assessment = enterpriseAssessment;\n\
    \n// replace with actual mock when it's possible to mock BigQuery.insert.\nenterpriseMockData.bigQueryInsertMock\
    \ = (connectionInfo, rows) => {  \n  return promise((resolve, reject) => reject('Some\
    \ error message.'));\n};\n\n// run the template code.\nrunCode(enterpriseMockData);\n\
    \n// assertions need to deferred due to async behaviors (promises).\ndefer(()\
    \ => {  \n  assertApi('logToConsole').wasCalled();\n  assertApi('runContainer').wasNotCalled();\n\
    \  assertApi('gtmOnSuccess').wasNotCalled();\n  assertApi('gtmOnFailure').wasCalled();\n\
    });"
- name: v3 - Failure - Output to BigQuery Only
  code: "v3MockData.outputToBigQuery = true;\nconst assessment = v3Assessment;\n\n\
    // replace with actual mock when it's possible to mock BigQuery.insert.\nenterpriseMockData.bigQueryInsertMock\
    \ = (connectionInfo, rows) => {  \n  return promise((resolve, reject) => reject('Some\
    \ error message.'));\n};\n\n// run the template code.\nrunCode(enterpriseMockData);\n\
    \n// assertions need to deferred due to async behaviors (promises).\ndefer(()\
    \ => {  \n  assertApi('logToConsole').wasCalled();\n  assertApi('runContainer').wasNotCalled();\n\
    \  assertApi('gtmOnSuccess').wasNotCalled();\n  assertApi('gtmOnFailure').wasCalled();\n\
    });"
- name: Enterprise - Success - Attach to Event Data Only
  code: "enterpriseMockData.attachToEventData = true;\nconst assessment = enterpriseAssessment;\n\
    \n// run the template code.\nrunCode(enterpriseMockData);\n\n// assertions need\
    \ to deferred due to async behaviors (promises).\ndefer(() => {  \n  assertThat(eventData).isEqualTo({\n\
    \    client_id: 'test-client-id',\n    ip_override: 'test-ip-address',\n    user_agent:\
    \ 'test-user-agent',\n    recaptcha_score: 0.7,\n    recaptcha_valid: true\n \
    \ });\n  \n  assertApi('runContainer').wasCalled();\n  assertApi('gtmOnSuccess').wasCalled();\n\
    });"
- name: v3 - Success - Attach to Event Data Only
  code: "v3MockData.attachToEventData = true;\nconst assessment = v3Assessment;\n\n\
    // run the template code.\nrunCode(v3MockData);\n\n// assertions need to deferred\
    \ due to async behaviors (promises).\ndefer(() => {  \n  assertThat(eventData).isEqualTo({\n\
    \    client_id: 'test-client-id',\n    ip_override: 'test-ip-address',\n    user_agent:\
    \ 'test-user-agent',\n    recaptcha_score: 0.8,\n    recaptcha_valid: true\n \
    \ });\n  \n  assertApi('runContainer').wasCalled();\n  assertApi('gtmOnSuccess').wasCalled();\n\
    });"
- name: Enterprise - Success - Attach to Event Data and Output to BigQuery
  code: "enterpriseMockData.attachToEventData = true;\nenterpriseMockData.outputToBigQuery\
    \ = true;\nconst assessment = enterpriseAssessment;\n\nlet params = {};\n// replace\
    \ with actual mock when it's possible to mock BigQuery.insert.\nenterpriseMockData.bigQueryInsertMock\
    \ = (connectionInfo, rows) => {\n  params.connectionInfo = connectionInfo;\n \
    \ params.rows = rows;\n  \n  return promise(resolve => resolve());\n};\n\n// run\
    \ the template code.\nrunCode(enterpriseMockData);\n\n// assertions need to deferred\
    \ due to async behaviors (promises).\ndefer(() => {\n  assertThat(params.connectionInfo).isEqualTo({\n\
    \    projectId: enterpriseMockData.cloudProjectId,\n    datasetId: enterpriseMockData.bigQueryDatasetId,\n\
    \    tableId: enterpriseMockData.bigQueryTableId\n  });\n  \n  assertThat(params.rows).isEqualTo([{\n\
    \    timestamp: assessment.tokenProperties.createTime,\n    client_id: 'test-client-id',\n\
    \    risk_analysis: {\n      score: assessment.riskAnalysis.score,\n      reasons:\
    \ assessment.riskAnalysis.reasons,\n      extended_verdict_reasons: assessment.riskAnalysis.extendedVerdictReasons\n\
    \    },\n    token_properties: {\n      valid: assessment.tokenProperties.valid,\n\
    \      invalid_reason: assessment.tokenProperties.invalidReason\n    }\n  }]);\n\
    \  \n  assertThat(eventData).isEqualTo({\n    client_id: 'test-client-id',\n \
    \   ip_override: 'test-ip-address',\n    user_agent: 'test-user-agent',\n    recaptcha_score:\
    \ 0.7,\n    recaptcha_valid: true\n  });\n  \n  assertApi('runContainer').wasCalled();\n\
    \  assertApi('gtmOnSuccess').wasCalled();\n});"
- name: v3 - Success - Attach to Event Data and Output to BigQuery
  code: "v3MockData.attachToEventData = true;\nv3MockData.outputToBigQuery = true;\n\
    const assessment = v3Assessment;\n\nlet params = {};\n// replace with actual mock\
    \ when it's possible to mock BigQuery.insert.\nv3MockData.bigQueryInsertMock =\
    \ (connectionInfo, rows) => {\n  params.connectionInfo = connectionInfo;\n  params.rows\
    \ = rows;\n  \n  return promise(resolve => resolve());\n};\n\n// run the template\
    \ code.\nrunCode(v3MockData);\n\n// assertions need to deferred due to async behaviors\
    \ (promises).\ndefer(() => {\n  assertThat(params.connectionInfo).isEqualTo({\n\
    \    projectId: v3MockData.cloudProjectId,\n    datasetId: v3MockData.bigQueryDatasetId,\n\
    \    tableId: v3MockData.bigQueryTableId\n  });\n  \n  assertThat(params.rows).isEqualTo([{\n\
    \    timestamp: assessment.challenge_ts,\n    client_id: 'test-client-id',\n \
    \   risk_analysis: {\n      score: assessment.score,\n      reasons: [],\n   \
    \   extended_verdict_reasons: []\n    },\n    token_properties: {\n      valid:\
    \ assessment.success,\n      invalid_reason: ''\n    }\n  }]);\n  \n  assertThat(eventData).isEqualTo({\n\
    \    client_id: 'test-client-id',\n    ip_override: 'test-ip-address',\n    user_agent:\
    \ 'test-user-agent',\n    recaptcha_score: 0.8,\n    recaptcha_valid: true\n \
    \ });\n  \n  assertApi('runContainer').wasCalled();\n  assertApi('gtmOnSuccess').wasCalled();\n\
    });"
setup: "const json = require('JSON');\nconst promise = require('Promise').create;\n\
  const defer = require('callLater');\n\nconst enterpriseMockData = {\n  version:\
  \ 'enterprise',\n  cloudProjectId: 'test-project-id',\n  apiKey: 'test-api-key',\n\
  \  siteKey: 'test-site-key',\n  attachToEventData: false,\n  outputToBigQuery: false,\n\
  \  bigQueryDatasetId: 'test-bq-dataset-id',\n  bigQueryTableId: 'test-bq-table-id',\n\
  \  loggingEnabled: true,\n  testing: true\n};\n\nconst v3MockData = {\n  version:\
  \ 'v3',\n  secretKey: 'test-secret-key',\n  attachToEventData: false,\n  outputToBigQuery:\
  \ false,\n  bigQueryDatasetId: 'test-bq-dataset-id',\n  bigQueryTableId: 'test-bq-table-id',\n\
  \  loggingEnabled: true,\n  testing: true\n};\n\nlet eventData;\nmock('runContainer',\
  \ function(rcEventData) {\n  eventData = rcEventData;\n});\n\nmock('getAllEventData',\
  \ {\n  client_id: 'test-client-id',\n  ip_override: 'test-ip-address',\n  user_agent:\
  \ 'test-user-agent',\n  recaptcha: '{\"token\": \"test-token\",\"action\": \"test-action\"\
  }'\n});\n\nmock('isRequestMpv2', true);\n\nconst enterpriseAssessment = {\n  event:\
  \ {\n    expectedAction: 'test-action',\n  },\n  riskAnalysis: {\n    score: 0.7,\n\
  \    reasons: ['TEST_REASON'],\n    extendedVerdictReasons: ['TEST_EXTENDED_VERDICT_REASON']\n\
  \  },\n  tokenProperties: {\n    valid: true,\n    action: 'test-action',\n    invalidReason:\
  \ 'INVALID_REASON_UNSPECIFIED',\n    createTime: '2023-04-28T20:41:30.166Z'\n  }\n\
  };\n\nconst v3Assessment = {\n  success: true,      \n  score: 0.8,\n  action: 'test-action',\n\
  \  challenge_ts: '2023-04-28T20:41:30.166Z',\n  'error-codes': []\n};\n\nlet httpRequest\
  \ = {};\nmock('sendHttpRequest', function(url, options, body) {\n  httpRequest.url\
  \ = url;\n  httpRequest.options = options;\n  httpRequest.body = body;\n  \n  return\
  \ promise(resolve => resolve({\n    statusCode: 200,\n    body: json.stringify(assessment)\n\
  \  }));\n});"


___NOTES___

Created on 5/8/2023, 3:46:49 PM


