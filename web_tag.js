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
const json = require('JSON');
const dataLayer = {
  push: createQueue('dataLayer')
};

const config = data.config;
const success = data.gtmOnSuccess;
const failure = data.gtmOnFailure;

ensureLibraryLoaded(() => {
  if (data.behavior === 'initialize') {
    success();
  } else {
    if (data.action) {
      generateToken(data.action, token => {
       if (data.behavior === 'assess') {
         saveToDataLayer(token, data.action);
       }
       success();
      }, failure);
    } else {
      failure();
    }
  }
}, failure);

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
 * If the library is loading this will wait until the it's completely loaded before resolving.
 * If the library is already loaded it will resolve immediately.
 *
 * @param {SuccessCallback} resolve
 * @param {FailureCallback} reject
 */
function ensureLibraryLoaded(resolve, reject) {
  injectScript(config.library + '?render=' + config.siteKey, resolve, reject, 'recaptcha_library');
}

/**
 * Takes a reCAPTCHA action and generates a token using the v3/enterprise API.
 *
 * @param {string} action
 * @param {SuccessCallback} resolve
 * @param {FailureCallback} reject
 */
function generateToken(action, resolve, reject) {
  const ready = copyFromWindow(config.readyMethod);
  ready(() => {
    const execute = copyFromWindow(config.executeMethod);
    execute(config.siteKey, { action: action })
      .then(resolve)
      .catch(reject);
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
      action: action,
      siteKey: config.siteKey
    })
  });
}