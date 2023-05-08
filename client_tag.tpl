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
  "description": "Handle reCAPTCHA library injection and token fetch then attach token to 'recaptcha' variable in the data layer.",
  "containerContexts": [
    "WEB"
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
    "name": "v3SiteKey",
    "displayName": "Site Key",
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
    "name": "enterpriseSiteKey",
    "displayName": "Enterprise Key ID",
    "simpleValueType": true,
    "enablingConditions": [
      {
        "paramName": "version",
        "paramValue": "enterprise",
        "type": "EQUALS"
      }
    ]
  }
]


___SANDBOXED_JS_FOR_WEB_TEMPLATE___

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


___WEB_PERMISSIONS___

[
  {
    "instance": {
      "key": {
        "publicId": "access_globals",
        "versionId": "1"
      },
      "param": [
        {
          "key": "keys",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "key"
                  },
                  {
                    "type": 1,
                    "string": "read"
                  },
                  {
                    "type": 1,
                    "string": "write"
                  },
                  {
                    "type": 1,
                    "string": "execute"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "grecaptcha.enterprise.ready"
                  },
                  {
                    "type": 8,
                    "boolean": true
                  },
                  {
                    "type": 8,
                    "boolean": false
                  },
                  {
                    "type": 8,
                    "boolean": true
                  }
                ]
              },
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "key"
                  },
                  {
                    "type": 1,
                    "string": "read"
                  },
                  {
                    "type": 1,
                    "string": "write"
                  },
                  {
                    "type": 1,
                    "string": "execute"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "grecaptcha.enterprise.execute"
                  },
                  {
                    "type": 8,
                    "boolean": true
                  },
                  {
                    "type": 8,
                    "boolean": false
                  },
                  {
                    "type": 8,
                    "boolean": true
                  }
                ]
              },
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "key"
                  },
                  {
                    "type": 1,
                    "string": "read"
                  },
                  {
                    "type": 1,
                    "string": "write"
                  },
                  {
                    "type": 1,
                    "string": "execute"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "dataLayer"
                  },
                  {
                    "type": 8,
                    "boolean": true
                  },
                  {
                    "type": 8,
                    "boolean": true
                  },
                  {
                    "type": 8,
                    "boolean": false
                  }
                ]
              },
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "key"
                  },
                  {
                    "type": 1,
                    "string": "read"
                  },
                  {
                    "type": 1,
                    "string": "write"
                  },
                  {
                    "type": 1,
                    "string": "execute"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "grecaptcha.ready"
                  },
                  {
                    "type": 8,
                    "boolean": true
                  },
                  {
                    "type": 8,
                    "boolean": false
                  },
                  {
                    "type": 8,
                    "boolean": true
                  }
                ]
              },
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "key"
                  },
                  {
                    "type": 1,
                    "string": "read"
                  },
                  {
                    "type": 1,
                    "string": "write"
                  },
                  {
                    "type": 1,
                    "string": "execute"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "grecaptcha.execute"
                  },
                  {
                    "type": 8,
                    "boolean": true
                  },
                  {
                    "type": 8,
                    "boolean": false
                  },
                  {
                    "type": 8,
                    "boolean": true
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
  },
  {
    "instance": {
      "key": {
        "publicId": "inject_script",
        "versionId": "1"
      },
      "param": [
        {
          "key": "urls",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 1,
                "string": "https://www.google.com/recaptcha/enterprise.js*"
              },
              {
                "type": 1,
                "string": "https://www.google.com/recaptcha/api.js*"
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
        "publicId": "read_data_layer",
        "versionId": "1"
      },
      "param": [
        {
          "key": "keyPatterns",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 1,
                "string": "event"
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
        "publicId": "get_url",
        "versionId": "1"
      },
      "param": [
        {
          "key": "urlParts",
          "value": {
            "type": 1,
            "string": "any"
          }
        },
        {
          "key": "queriesAllowed",
          "value": {
            "type": 1,
            "string": "any"
          }
        }
      ]
    },
    "isRequired": true
  }
]


___TESTS___

scenarios:
- name: Enterprise - Initialization
  code: |-
    const mockData = {
      version: 'enterprise',
      enterpriseSiteKey: 'enterprise-site-key'
    };

    mock('copyFromDataLayer', 'gtm.init');

    // Call runCode to run the template's code.
    runCode(mockData);

    assertThat(injectedScript).isEqualTo(
      'https://www.google.com/recaptcha/enterprise.js?render=enterprise-site-key');

    assertThat(dataLayer).isEqualTo([{
      event: 'reCAPTCHA Loaded'
    }]);
- name: v3 - Initialization
  code: |-
    const mockData = {
      version: 'v3',
      v3SiteKey: 'v3-site-key'
    };

    mock('copyFromDataLayer', 'gtm.init');

    // Call runCode to run the template's code.
    runCode(mockData);

    assertThat(injectedScript).isEqualTo(
      'https://www.google.com/recaptcha/api.js?render=v3-site-key');

    assertThat(dataLayer).isEqualTo([{
      event: 'reCAPTCHA Loaded'
    }]);
- name: Enterprise - Get Token
  code: |
    const mockData = {
      version: 'enterprise',
      enterpriseSiteKey: 'enterprise-site-key'
    };

    mock('copyFromDataLayer', 'gtm.submit');

    // Call runCode to run the template's code.
    runCode(mockData);

    // Verify that the tag finished successfully.
    assertThat(siteKey).isEqualTo('enterprise-site-key');
    assertThat(action).isEqualTo('sha256-action');
    assertThat(dataLayer).isEqualTo([{
      recaptcha: '{"token":"recaptcha-token","action":"sha256-action"}'
    }]);
- name: v3 - Get Token
  code: |
    const mockData = {
      version: 'v3',
      v3SiteKey: 'v3-site-key'
    };

    mock('copyFromDataLayer', 'gtm.submit');

    // Call runCode to run the template's code.
    runCode(mockData);

    // Verify that the tag finished successfully.
    assertThat(siteKey).isEqualTo('v3-site-key');
    assertThat(action).isEqualTo('sha256-action');
    assertThat(dataLayer).isEqualTo([{
      recaptcha: '{"token":"recaptcha-token","action":"sha256-action"}'
    }]);
setup: |-
  let dataLayer = [];
  mock('createQueue', name => {
    return item => dataLayer.push(item);
  });

  let injectedScript;
  mock('injectScript', (url, resolve, reject) => {
    injectedScript = url;
    resolve();
  });

  mock('sha256', (text, callback) => {
    callback('sha256-action');
  });

  let siteKey, action;
  mock('copyFromWindow', methodName => {
    if (methodName.match('ready')) {
      return callback => callback();
    } else if (methodName.match('execute')) {
      return (key, options) => {
        siteKey = key;
        action = options.action;
        return {
          then: callback => {
            callback('recaptcha-token');
            return {
              catch: () => {}
            };
          }
        };
      };
    }
  });


___NOTES___

Created on 5/8/2023, 3:29:25 PM

