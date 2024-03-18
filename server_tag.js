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

const auth = require('getGoogleAuth')({
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
});

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
    const url = enterpriseApiUrl + '/projects/' + data.cloudProjectId + '/assessments';
    const body = json.stringify({
      event: {
        token: recaptcha.token,
        siteKey: recaptcha.siteKey,
        expectedAction: recaptcha.action,
        userIpAddress: eventData.ip_override,
        userAgent: eventData.user_agent
      }
    });

    sendHttpRequest(url, {
      headers: {
        'Content-Type': 'application/json; charset=utf-8'
      },
      authorization: auth,
      method: 'POST',
      timeout: 5000
    }, body)
    .then(response => {
      if (response.statusCode === 200) {
        const assessment = json.parse(response.body);
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
    projectId: data.bigQueryCloudProjectId,
    datasetId: data.bigQueryDatasetId,
    tableId: data.bigQueryTableId
  };

  return promise((resolve, reject) => {
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
