___INFO___

{
  "type": "MACRO",
  "id": "cvt_temp_public_id",
  "version": 1,
  "securityGroups": [],
  "displayName": "reCAPTCHA",
  "description": "Handle parsing and interpreting the reCAPTCHA token.",
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
    "macrosInSelect": false,
    "selectItems": [
      {
        "value": "v3",
        "displayValue": "V3"
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
    "type": "SELECT",
    "name": "type",
    "displayName": "Type",
    "macrosInSelect": false,
    "selectItems": [
      {
        "value": "json",
        "displayValue": "reCAPTCHA Assessment (JSON)"
      },
      {
        "value": "number",
        "displayValue": "reCAPTCHA Score (Number)"
      }
    ],
    "simpleValueType": true
  },
  {
    "type": "TEXT",
    "name": "defaultValueOnError",
    "displayName": "Error Value (If Error Occurs)",
    "simpleValueType": true
  },
  {
    "type": "TEXT",
    "name": "defaultValueOnMissing",
    "displayName": "N/A Value (If reCAPTCHA Data Not Present)",
    "simpleValueType": true
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

// capture start-time very first to ensure accurate performance checks.
const timestamp = require('getTimestampMillis');
const startTime = timestamp();

// globals
const siteVerifyUrl = 'https://www.google.com/recaptcha/api/siteverify';
const enterpriseApiUrl = 'https://recaptchaenterprise.googleapis.com/v1';
const processing = 'PROCESSING';

// request and response specific methods.
const request = {
  isAnalytics: require('isRequestMpv2'),
  eventData: require('getAllEventData')
};

// utility classes/methods.
const logToConsole = require('logToConsole');
const sendHttpRequest = require('sendHttpRequest');
const promise = require('Promise').create;
const deleteProperty = require('Object').delete;
const encodeUriComponent = require('encodeUriComponent');
const JSON = require('JSON');
const addEventCallback = require('addEventCallback');
const templateDataStorage = require('templateDataStorage');
const sha256 = require('sha256Sync');
const hashify = (data) => sha256(JSON.stringify(data));
const storage = {
  set: templateDataStorage.setItemCopy,
  get: (key) => {
    let value = templateDataStorage.getItemCopy(key);
    if (value === processing) {
        defer(() => {
          storage.get(key);
        });
    } else {
      return value;
    }
  },
  remove: templateDataStorage.removeItem
};
const auth = require('getGoogleAuth')({
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
});
const defer = require('callLater');

if (request.isAnalytics()) {
  const eventData = request.eventData();

  if (!eventData.recaptcha) {
    return data.defaultValueOnMissing;
  }

  let hash = hashify(eventData);
  let assessment = storage.get(hash);
  if (assessment) {
    log('Returning cached reCAPTCHA assessment...');
    return assessment;
  }

  storage.set(hash, processing);
  log('Processing reCAPTCHA...');
  addEventCallback(() => storage.remove(hash));

  return getAssessment(eventData)
    .then(assessment => {
      if (data.type === 'json') {
        deleteProperty(assessment.event, 'token');
        storage.set(hash, assessment);
        return assessment;
      } else {
        storage.set(hash, assessment.riskAnalysis.score);
        return assessment.riskAnalysis.score;
      }
    })
    .catch(error => {
      log(error);
      return data.defaultValueOnError;
    });
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
    const recaptcha = JSON.parse(eventData.recaptcha);

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
        const assessment = JSON.parse(response.body);
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
    const url = enterpriseApiUrl + '/projects/' + data.cloudProjectId + '/assessments';
    const body = JSON.stringify({
      event: {
        token: recaptcha.token,
        siteKey: recaptcha.siteKey,
        expectedAction: recaptcha.action,
        userIpAddress: eventData.ip_override,
        userAgent: eventData.user_agent
      }
    });

    log(url, body);

    sendHttpRequest(url, {
      headers: {
        'Content-Type': 'application/json; charset=utf-8'
      },
      authorization: auth,
      method: 'POST',
      timeout: 5000
    }, body)
    .then(response => {
      log(response.statusCode, response.body);
      if (response.statusCode === 200) {
        const assessment = JSON.parse(response.body);
        const actionMatches = assessment.tokenProperties.action === assessment.event.expectedAction;
        assessment.tokenProperties.valid = actionMatches && assessment.tokenProperties.valid;
        if (assessment.tokenProperties.createTime === '1970-01-01T00:00:00Z') {
          assessment.tokenProperties.createTime = null;
        }
        resolve(assessment);
      } else {
        reject(response.body);
      }
    })
    .catch(reject);
  });
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
    const starter = '[reCAPTCHA Variable]' + ' [' + (timestamp() - startTime) + 'ms]';
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
        "publicId": "use_google_credentials",
        "versionId": "1"
      },
      "param": [
        {
          "key": "allowedScopes",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 1,
                "string": "https://www.googleapis.com/auth/cloud-platform"
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
        "publicId": "read_event_metadata",
        "versionId": "1"
      },
      "param": []
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "access_template_storage",
        "versionId": "1"
      },
      "param": []
    },
    "isRequired": true
  }
]


___TESTS___

scenarios:
- name: Enterprise - JSON - Success
  code: |-
    enterpriseMockData.type = 'json';
    const assessment = enterpriseAssessment;
    templateDataStorage.removeItem(hash);

    // run the template code.
    runCode(enterpriseMockData).then(result => {
      assertThat(result).isEqualTo(enterpriseAssessment);
    });
- name: Enterprise - Number - Success
  code: |-
    enterpriseMockData.type = 'number';
    const assessment = enterpriseAssessment;
    templateDataStorage.removeItem(hash);

    // run the template code.
    runCode(enterpriseMockData).then(result => {
      assertThat(result).isEqualTo(enterpriseAssessment.riskAnalysis.score);
    });
- name: Enterprise - 500 Failure
  code: "enterpriseMockData.type = 'json';\nenterpriseMockData.defaultValueOnError\
    \ = 'failure';\nconst assessment = enterpriseAssessment;\ntemplateDataStorage.removeItem(hash);\n\
    \nmock('sendHttpRequest', function(url, options, body) {  \n  return promise(resolve\
    \ => resolve({\n    statusCode: 500,\n    body: 'Unknown Error'\n  }));\n});\n\
    \n// run the template code.\nrunCode(enterpriseMockData).then(result => {\n  assertThat(result).isEqualTo(enterpriseMockData.defaultValueOnError);\n\
    });"
- name: Enterprise - Unknown Failure
  code: "enterpriseMockData.type = 'json';\nenterpriseMockData.defaultValueOnError\
    \ = 'failure';\nconst assessment = enterpriseAssessment;\ntemplateDataStorage.removeItem(hash);\n\
    \nmock('sendHttpRequest', function(url, options, body) {  \n  return promise((resolve,\
    \ reject) => reject('error'));\n});\n\n// run the template code.\nrunCode(enterpriseMockData).then(result\
    \ => {\n  assertThat(result).isEqualTo(enterpriseMockData.defaultValueOnError);\n\
    });"
- name: V3 - JSON - Success
  code: |-
    v3MockData.type = 'json';
    const assessment = v3Assessment;
    templateDataStorage.removeItem(hash);

    // run the template code.
    runCode(v3MockData).then(result => {
      assertThat(result).isEqualTo({
        riskAnalysis: {
          score: v3Assessment.score,
          reasons: [],
          extendedVerdictReasons: []
        },
        tokenProperties: {
          valid: true,
          invalidReason: '',
          createTime: v3Assessment.challenge_ts,
          hostname: v3Assessment.hostname,
          action: v3Assessment.action
        }
      });
    });
- name: V3 - Number - Success
  code: |-
    v3MockData.type = 'number';
    const assessment = v3Assessment;
    templateDataStorage.removeItem(hash);

    // run the template code.
    runCode(v3MockData).then(result => {
      assertThat(result).isEqualTo(v3Assessment.score);
    });
- name: V3 - 500 Failure
  code: "v3MockData.type = 'json';\nv3MockData.defaultValueOnError = 'failure';\n\
    const assessment = v3Assessment;\ntemplateDataStorage.removeItem(hash);\n\nmock('sendHttpRequest',\
    \ function(url, options, body) {  \n  return promise(resolve => resolve({\n  \
    \  statusCode: 500,\n    body: 'Unknown Error'\n  }));\n});\n\n// run the template\
    \ code.\nrunCode(v3MockData).then(result => {\n  assertThat(result).isEqualTo(v3MockData.defaultValueOnError);\n\
    });"
- name: V3 - Unknown Failure
  code: "v3MockData.type = 'json';\nv3MockData.defaultValueOnError = 'failure';\n\
    const assessment = v3Assessment;\ntemplateDataStorage.removeItem(hash);\n\nmock('sendHttpRequest',\
    \ function(url, options, body) {  \n  return promise((resolve, reject) => reject('error'));\n\
    });\n\n// run the template code.\nrunCode(v3MockData).then(result => {\n  assertThat(result).isEqualTo(v3MockData.defaultValueOnError);\n\
    });"
- name: No reCAPTCHA Present in Event Returns Default Missing Value
  code: |-
    enterpriseMockData.type = 'json';
    enterpriseMockData.defaultValueOnMissing = 'n/a';
    const assessment = enterpriseAssessment;
    templateDataStorage.removeItem(hash);

    mock('getAllEventData', {
      client_id: 'test-client-id',
      ip_override: 'test-ip-address',
      user_agent: 'test-user-agent',
      recaptcha: ''
    });

    // run the template code.
    assertThat(runCode(enterpriseMockData))
      .isEqualTo(enterpriseMockData.defaultValueOnMissing);
- name: Cache Returned When Available
  code: |-
    enterpriseMockData.type = 'json';
    const assessment = enterpriseAssessment;
    templateDataStorage.removeItem(hash);

    // run the template code.
    runCode(enterpriseMockData).then(result => {
      assertThat(runCode(enterpriseMockData)).isEqualTo(enterpriseAssessment);
    });
setup: "const json = require('JSON');\nconst promise = require('Promise').create;\n\
  const defer = require('callLater');\nconst templateDataStorage = require('templateDataStorage');\n\
  const sha256 = require('sha256Sync');\nconst hashify = (data) => sha256(json.stringify(data));\n\
  \nconst enterpriseMockData = {\n  version: 'enterprise',\n  cloudProjectId: 'test-project-id',\n\
  \  type: 'json',\n  loggingEnabled: true,\n  \n};\n\nconst v3MockData = {\n  version:\
  \ 'v3',\n  secretKey: 'test-secret-key',\n  type: 'json',\n  loggingEnabled: true\n\
  };\n\nlet eventData;\nmock('getAllEventData', {\n  client_id: 'test-client-id',\n\
  \  ip_override: 'test-ip-address',\n  user_agent: 'test-user-agent',\n  recaptcha:\
  \ '{\"token\":\"test-token\",\"action\":\"test-action\",\"siteKey\":\"test-site-key\"\
  }'\n});\nlet hash = hashify({\n  client_id: 'test-client-id',\n  ip_override: 'test-ip-address',\n\
  \  user_agent: 'test-user-agent',\n  recaptcha: '{\"token\":\"test-token\",\"action\"\
  :\"test-action\",\"siteKey\":\"test-site-key\"}'\n});\n\nmock('isRequestMpv2', true);\n\
  \nconst enterpriseAssessment = {\n  event: {\n    expectedAction: 'test-action',\n\
  \  },\n  riskAnalysis: {\n    score: 0.7,\n    reasons: ['TEST_REASON'],\n    extendedVerdictReasons:\
  \ ['TEST_EXTENDED_VERDICT_REASON']\n  },\n  tokenProperties: {\n    valid: true,\n\
  \    action: 'test-action',\n    invalidReason: 'INVALID_REASON_UNSPECIFIED',\n\
  \    createTime: '2023-04-28T20:41:30.166Z'\n  }\n};\n\nconst v3Assessment = {\n\
  \  success: true,      \n  score: 0.8,\n  action: 'test-action',\n  challenge_ts:\
  \ '2023-04-28T20:41:30.166Z',\n  'error-codes': []\n};\n\nlet httpRequest = {};\n\
  mock('sendHttpRequest', function(url, options, body) {\n  httpRequest.url = url;\n\
  \  httpRequest.options = options;\n  httpRequest.body = body;\n  \n  return promise(resolve\
  \ => resolve({\n    statusCode: 200,\n    body: json.stringify(assessment)\n  }));\n\
  });"


___NOTES___

Created on 3/25/2024, 12:29:47 PM


