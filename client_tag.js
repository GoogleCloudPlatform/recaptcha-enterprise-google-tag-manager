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

const injectScript = require('injectScript');
const copyFromWindow = require('copyFromWindow');
const createQueue = require('createQueue');
const sha256 = require('sha256');
const pagePath = require('getUrl')('path');
const json = require('JSON');
const dataLayer = {
  push: createQueue('dataLayer'),
  get: require('copyFromDataLayer')
};

const configurations = {
  v3: {
    library: 'https://www.google.com/recaptcha/api.js',
    siteKey: data.v3SiteKey,
    readyMethod: 'grecaptcha.ready',
    executeMethod: 'grecaptcha.execute'
  },
  enterprise: {
    library: 'https://www.google.com/recaptcha/enterprise.js',
    siteKey: data.enterpriseSiteKey,
    readyMethod: 'grecaptcha.enterprise.ready',
    executeMethod: 'grecaptcha.enterprise.execute'
  }
};

const config = configurations[data.version];
const trigger = dataLayer.get('event');

if (trigger === 'gtm.init') {
  injectLibrary(() => {
    sendLoadedEvent();
    data.gtmOnSuccess();
  }, data.gtmOnFailure);
} else {
  buildAction(action => {
    getToken(action, token => {
     saveToDataLayer(token, action);
     data.gtmOnSuccess();
    }, data.gtmOnFailure);
  });
}

/**
 * This is called once the function it's provided to has completed successfully.
 *
 * @callback SuccessCallback
 */

/**
 * This is called in the event the function it's provided to has failed to complete successfully.
 *
 * @callback FailureCallback
 */

/**
 * Inject the appropriate reCAPTCHA library (v3/enterprise) into the page that's
 * necessary for generating a reCAPTCHA token.
 *
 * @param {SuccessCallback} resolve
 * @param {FailureCallback} reject
 */
function injectLibrary(resolve, reject) {
  injectScript(config.library + '?render=' + config.siteKey, resolve, reject);
}

/**
 * Takes a reCAPTCHA action and generates a token using the v3/enterprise API.
 *
 * @param {string} action
 * @param {SuccessCallback} resolve
 * @param {FailureCallback} reject
 */
function getToken(action, resolve, reject) {
  const ready = copyFromWindow(config.readyMethod);
  ready(() => {
    const execute = copyFromWindow(config.executeMethod);
    execute(config.siteKey, { action: action })
      .then(resolve)
      .catch(reject);
  });
}

/**
 * Adds the reCAPTCHA Loaded event to the data layer. This is used to trigger a page load
 * event if necessary (as the library has to be loaded before you can generate a token).
 */
function sendLoadedEvent() {
  dataLayer.push({
    event: 'reCAPTCHA Loaded'
  });
}

/**
 * Adds the reCAPTCHA token (encrypted data) and the action to the data layer. This is what
 * should be attached to any event for which this tag has been added as a setup tag.
 *
 * @param {string} token
 * @param {string} action
 */
function saveToDataLayer(token, action) {
  dataLayer.push({
    recaptcha: json.stringify({
      token: token,
      action: action
    })
  });
}

/**
 * Generates a unique hash that includes page path and event trigger. This hash is used on the
 * backend to ensure the request is a valid one and no tampering is happening in an attempt to
 * fake a request by using a valid token from another page/event.
 *
 * @param {SuccessCallback} resolve
 */
function buildAction(resolve) {
  sha256(pagePath + trigger, actionId => {
    // actions cannot have = or + characters and SHA256 hashes
    // can contain these so they need to be removed.
    resolve(actionId.replace('=', '').replace('+', ''));
  });
}