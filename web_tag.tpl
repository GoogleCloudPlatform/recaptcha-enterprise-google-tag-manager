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
  "description": "Handle reCAPTCHA library injection, calling of reCAPTCHA execute to gather data, and if assessing an action then saves the response token from reCAPTCHA to the data layer.",
  "containerContexts": [
    "WEB"
  ]
}


___TEMPLATE_PARAMETERS___

[
  {
    "type": "TEXT",
    "name": "config",
    "displayName": "Config",
    "simpleValueType": true,
    "help": "Use the configuration variable you created with the reCAPTCHA variable template provided with the solution."
  },
  {
    "type": "SELECT",
    "name": "behavior",
    "displayName": "Behavior",
    "selectItems": [
      {
        "value": "initialize",
        "displayValue": "Initialize"
      },
      {
        "value": "gatherData",
        "displayValue": "Gather Data"
      },
      {
        "value": "assess",
        "displayValue": "Assess"
      }
    ],
    "simpleValueType": true,
    "help": "Are you initializing the reCAPTCHA library (on page initialization), gathering data via the reCAPTCHA library (calling execute to capture an action), or assessing the action in real-time (calling execute to capture an action and then saving the reCAPTCHA payload to the data layer to be sent with an event and assessed by sGTM and the reCAPTCHA Enterprise API)."
  },
  {
    "type": "TEXT",
    "name": "action",
    "displayName": "Action",
    "simpleValueType": true,
    "help": "This will be sent to reCAPTCHA as the action name. Should be human readable must only included alphabetic characters (a-z) or underscores (_).",
    "valueValidators": [
      {
        "type": "REGEX",
        "args": [
          "^[a-zA-Z_]+$"
        ]
      },
      {
        "type": "NON_EMPTY"
      }
    ],
    "enablingConditions": [
      {
        "paramName": "behavior",
        "paramValue": "initialize",
        "type": "NOT_EQUALS"
      }
    ]
  },
  {
    "type": "LABEL",
    "name": "initializeLabel",
    "displayName": "\u003cbr\u003e\u003cstrong\u003eRequirements:\u003c/strong\u003e\u003cbr\u003e\nThe Initialize behavior requires the \"Initialization - All Pages\" trigger to be added to this tag in order for it to operate properly.\u003cbr\u003e\u0026nbsp;",
    "enablingConditions": [
      {
        "paramName": "behavior",
        "paramValue": "initialize",
        "type": "EQUALS"
      }
    ]
  },
  {
    "type": "LABEL",
    "name": "gatherDataLabel",
    "displayName": "\u003cbr\u003e\u003cstrong\u003eRequirements:\u003c/strong\u003e\u003cbr\u003e The Gather Data behavior requires there be at least one trigger added directly to this tag in order for it to operate properly.\u003cbr\u003e\u0026nbsp;",
    "enablingConditions": [
      {
        "paramName": "behavior",
        "paramValue": "gatherData",
        "type": "EQUALS"
      }
    ]
  },
  {
    "type": "LABEL",
    "name": "assessLabel",
    "displayName": "\u003cbr\u003e\u003cstrong\u003eRequirements:\u003c/strong\u003e\u003cbr\u003e The Assess behavior requires there be no trigger added directly to this tag in order for it to operate properly. Instead add this tag to the GA4 Event tag you want to associate with this action as a Setup Tag under Advanced Settings \u003e Tag Sequencing \u003e Fire a tag before. Once this is done, add an Event Parameter to that same GA4 Event tag called recaptcha that targets the recaptcha object in the data layer (which will be added by this tag).\u003cbr\u003e\u0026nbsp;",
    "enablingConditions": [
      {
        "paramName": "behavior",
        "paramValue": "assess",
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
  }
]


___TESTS___

scenarios:
- name: Enterprise - Initialization
  code: |-
    const mockData = {
      config: enterpriseConfig,
      behavior: 'initialize'
    };

    // Call runCode to run the template's code.
    runCode(mockData);

    assertThat(injectedScript).isEqualTo(
      'https://www.google.com/recaptcha/enterprise.js?render=enterprise-site-key');
- name: v3 - Initialization
  code: |-
    const mockData = {
      config: v3Config,
      behavior: 'initialize'
    };

    // Call runCode to run the template's code.
    runCode(mockData);

    assertThat(injectedScript).isEqualTo(
      'https://www.google.com/recaptcha/api.js?render=v3-site-key');
- name: Enterprise - Assess
  code: |+
    const mockData = {
      config: enterpriseConfig,
      behavior: 'assess',
      action: 'test-action'
    };

    // Call runCode to run the template's code.
    runCode(mockData);

    // Verify that the tag finished successfully.
    assertThat(siteKey).isEqualTo('enterprise-site-key');
    assertThat(action).isEqualTo('test-action');
    assertThat(dataLayer).isEqualTo([{
      recaptcha: '{"token":"recaptcha-token","action":"test-action","siteKey":"enterprise-site-key"}'
    }]);

- name: Enterprise - Gather Data
  code: |+
    const mockData = {
      config: enterpriseConfig,
      behavior: 'gatherData',
      action: 'test-action'
    };

    // Call runCode to run the template's code.
    runCode(mockData);

    // Verify that the tag finished successfully.
    assertThat(siteKey).isEqualTo('enterprise-site-key');
    assertThat(action).isEqualTo('test-action');
    assertThat(dataLayer).isEqualTo([]);

- name: v3 - Assess
  code: |
    const mockData = {
      config: v3Config,
      behavior: 'assess',
      action: 'test-action-v3'
    };

    // Call runCode to run the template's code.
    runCode(mockData);

    // Verify that the tag finished successfully.
    assertThat(siteKey).isEqualTo('v3-site-key');
    assertThat(action).isEqualTo('test-action-v3');
    assertThat(dataLayer).isEqualTo([{
      recaptcha: '{"token":"recaptcha-token","action":"test-action-v3","siteKey":"v3-site-key"}'
    }]);
- name: v3 - Gather Data
  code: |
    const mockData = {
      config: v3Config,
      behavior: 'gatherData',
      action: 'test-action-v3'
    };

    // Call runCode to run the template's code.
    runCode(mockData);

    // Verify that the tag finished successfully.
    assertThat(siteKey).isEqualTo('v3-site-key');
    assertThat(action).isEqualTo('test-action-v3');
    assertThat(dataLayer).isEqualTo([]);
setup: |-
  const enterpriseConfig = {
    library: 'https://www.google.com/recaptcha/enterprise.js',
    siteKey: 'enterprise-site-key',
    readyMethod: 'grecaptcha.enterprise.ready',
    executeMethod: 'grecaptcha.enterprise.execute'
  };

  const v3Config = {
    library: 'https://www.google.com/recaptcha/api.js',
    siteKey: 'v3-site-key',
    readyMethod: 'grecaptcha.ready',
    executeMethod: 'grecaptcha.execute'
  };

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

Created on 12/1/2023, 3:04:22 PM


