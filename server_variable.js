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
const defer = require('callLater');
const storage = {
  set: templateDataStorage.setItemCopy,
  get: (key) => {
    return promise(resolve => {
      let value = templateDataStorage.getItemCopy(key);
      if (value === processing) {
          defer(() => {
            storage.get(key).then(resolve);
          });
      } else {
        resolve(value);
      }
    });
  },
  remove: templateDataStorage.removeItem
};
const auth = require('getGoogleAuth')({
  scopes: ['https://www.googleapis.com/auth/cloud-platform']
});

if (request.isAnalytics()) {
  const eventData = request.eventData();

  if (!eventData.recaptcha) {
    return data.defaultValueOnMissing;
  }

  let hash = hashify(eventData);
  return getAssessment(eventData, hash)
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
 * Gets the assessment (score, validity, etc) by providing the reCAPTCHA data to the
 * appropriate endpoint or by returning it directly from cache where applicable.
 *
 * @param {Object} eventData Contains all data pulled from the request that came into sGTM.
 * @param {string} eventData.recaptcha The reCAPTCHA data JSON string that contains token and action.
 * @param {string} hash The hash of the eventData.
 * @returns {Promise<Object>} The reCAPTCHA assessment containing score, token validity, and reasons for score.
 */
function getAssessment(eventData, hash) {
  return promise((resolve, reject) => {
    storage.get(hash)
      .then(assessment => {
        if (assessment) {
          log('Returning cached reCAPTCHA assessment...');
          resolve(assessment);
          return;
        }

        storage.set(hash, processing);
        log('Processing reCAPTCHA...');
        addEventCallback(() => storage.remove(hash));

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
      })
      .catch(reject);
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
      },
      assessmentEnvironment: {
        client: 'server-side-google-tag-manager',
        version: 'github-gcp-recaptcha-enterprise-google-tag-manager-1.0.0'
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