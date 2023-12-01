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

const config = {
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

  return config[data.version];