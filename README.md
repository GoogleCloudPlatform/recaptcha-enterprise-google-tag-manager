# Lead QA (Quality Assurance) Documentation

Copyright 2023 Google LLC.

> **Important:** This is not an officially supported Google product. This solution, including any related sample code or data, is made available on an "as is," "as available," and "with all faults" basis, solely for illustrative purposes, and without warranty or representation of any kind. This solution is experimental, unsupported and provided solely for your convenience. Your use of it is subject to your agreements with Google, as applicable, and may constitute a beta feature as defined under those agreements. To the extent that you make any data available to Google in connection with your use of the solution, you represent and warrant that you have all necessary and appropriate rights, consents and permissions to permit Google to use and process that data. By using any portion of this solution, you acknowledge, assume and accept all risks, known and unknown, associated with its usage and any processing of data by Google, including with respect to your deployment of any portion of this solution in your systems, or usage in connection with your business, if at all. With respect to the entrustment of personal information to Google, you will verify that the established system is sufficient by checking Google's privacy policy and other public information, and you agree that no further information will be provided by Google.

## Description
This set of tag templates both run the reCAPTCHA library to generate a reCAPTCHA token and send the token to the reCAPTCHA API to interpret it and get a score. This score can be attached to the event data and the tags called again, saved to a BigQuery table of your choosing, or both.

An alternative library (recaptcha.js) has also been included for those who don't use or can't use Google Tag Manager (GTM) and Server-side Google Tag Manager (sGTM). This library is a simple wrapper around reCAPTCHA that makes implementing on your site more straightforward.

## What's the Purpose of This Score?
* If associated with the event data it can be used as a real-time indicator of the quality of a lead to filter out low quality (bot/spam/bad actor/etc) conversion events.
* If saved to BigQuery or associated to Google Analytics events as a user property or custom parameter it can be pulled later and connected to the form data via the client ID to avoid sending low quality leads downstream (automated process lead quality indicator) or avoid the manual effort required to follow up with low quality leads (visual lead quality indicator).

## Requirements
1. Lead form data submitted at the time the token is generated must have the GA4 client ID attached to it in some way when persisted to a datastore. This is necessary to tie the form data to the score.
2. Must be using both Google Tag Manager (GTM) and server-side Google Tag Manager (sGTM).


## Installation and Configuration
### Download the Repository and Unzip/Extract
1. [Download the repository](https://professional-services.googlesource.com/solutions/lead_qa/+archive/refs/heads/main.tar.gz) and extract the contents.
2. The **web_tag.tpl**, **web_config_variable.tpl**, **server_tag.tpl** files are the .tpl files you'll need for the next steps.

### BigQuery Setup
(Necessary if Planning to Save Scores in BigQuery Table)
* **If comfortable running the setup script:**
    * Run the bigquery_setup.sh script in this repository/directory.
* **If setting up manually:**
    * [Enable the BigQuery API](https://console.cloud.google.com/marketplace/product/google/bigquery.googleapis.com).
    * Use the bigquery_schema.json in this repository as the table schema/specification to manually create a new table.
    * This dataset and table will need permissions added for the sGTM service account (if sGTM is running outside of Google Cloud ensure [this step](https://developers.google.com/tag-platform/tag-manager/server-side/manual-setup-guide#optional_include_google_cloud_credentials) was done) in order for sGTM to access and insert data into this table. To do this find the dataset and table in [BigQuery Explorer](https://console.cloud.google.com/bigquery), select them (one at a time), and select **Sharing > Permissions > Add Principal**, enter the service account email address, and then assign the **BigQuery Data Viewer** role to the dataset and the **BigQuery Data Editor** role to the table.

### reCAPTCHA Setup
* **V3:**
    * [Register website with reCAPTCHA](https://www.google.com/recaptcha/admin/create). This will give you the necessary **Site Key** and **Secret Key**.
        * **Important:** Do not use the same Site Key for multiple websites/domains. If configured this way it will not work properly. Create and use multiple Site Keys where necessary.
    * If you already have a **Site Key** and **Secret Key** you can view it within [reCAPTCHA admin](https://www.google.com/recaptcha/admin/) by clicking on the gear icon (settings) in the top right.
    * Once you have your **Site Key** enter it within the web tag configuration.
    * Once you have your **Secret Key** enter it within the server-side tag configuration.
* **Enterprise:**
    * [Enable the reCAPTCHA Enterprise API](https://console.cloud.google.com/marketplace/product/google/recaptchaenterprise.googleapis.com).
    * [Create a reCAPTCHA Enterprise key](https://console.cloud.google.com/security/recaptcha/create).
        * **Important:** Do not use the same Enterprise Key ID for multiple websites/domains. If configured this way it will not work properly. Create and use multiple Enterprise Key IDs where necessary.
    * Once created copy your **Enterprise Key ID** (listed as ID at the top with a copy button next to it) and enter it within the web tag configuration.
    * [Open **Credentials** in Google Cloud](https://console.cloud.google.com/apis/credentials) and create an API key for reCAPTCHA Enterprise API (Create Credentials **>** API key).
    * Once created select **Edit API key** under **Actions** (three dots).
    * Restrict it to the **IP Addresses** of your server-side Google Tag Manager instance under **application restriction** (if possible) and restrict it to the **reCAPTCHA Enterprise API** under **API restrictions**.
    * Copy the **API Key** (top right) and paste this within the server-side tag configuration under **Enterprise API Key**.

### Server-side Tag Setup
#### Import the Server-side Google Tag Manager Tag Template
1. Once looking at the server-side container within Tag Manager select **Templates** in the left menu.
2. On the templates page next to **Tag Templates** select **New**.
3. From here select the **three vertical dots menu** next to save and select **Import**.
4. Select the **Server Tag template** (server_tag.tpl file as mentioned above) and once loaded select **Save** in the upper right corner.

#### Create & Configure the Tag That Will Use This Template
1. Once looking at the server-side container within Tag Manager select **Tags** in the left menu.
2. On the tags page next to **Tags** select **New**.
3. Change the name in the top left to something more identifiable for the purpose such as **reCAPTCHA Tag**.
4. Select anywhere in the **Tag Configuration** box.
5. In the menu that appears select **reCAPTCHA Tag**.
6. Select the appropriate **Version** of reCAPTCHA (V3 for personal use and Enterprise for business use).
7. Enter the necessary configuration settings for the version selected (see above **reCAPTCHA Setup** for details on how to acquire these).
8. Select where the score should end up.
    * Attached to Event Data.
        * Useful for attributing it to a Google Analytics event as a custom parameter or user property.
        * Also useful for real-time conversion filtering (configuring a trigger for the conversion tag whereby if the score is below a certain number then don't fire for example). **Be careful using this approach right away. There is a rampup period for reCAPTCHA Enterprise and as such the scores are not immediately accurate.**
    * Stored in a BigQuery table.
        * Useful for attributing it to the form data for an lead quality indicator for automated processes.
        * Can be used as a visual indicator if pulled into a CRM and associated with the form data.
        * **Important:** Using BigQuery requires some upfront configuration (see above **BigQuery Setup** for details).
    * Or both.
9. Create and attach **Trigger** that fires when the **recaptcha** event parameter exists.
    * Click in the **Triggering** box, click on the plus (**+**) and within the **Choose a Trigger** window select the plus (**+**) in the top right corner.
    * Click within the **Trigger Configuration** box and select **Custom**.
    * Under **This trigger fires on** select **Some Events**.
    * In the left dropdown select **New Variable...**, click on the **Variable Configuration** box and select **Event Data** under **Utilities**, in the **Key Path** field type **recaptcha**, name the variable (top left - defaults to "Untitled Variable"), and then **Save** the variable (top right).
    * In the middle dropdown select **starts with**.
    * In the right input box type **{** (this tells it to look for a recaptcha event property that looks like a JSON object - starts with an open curly bracket).
    * Give the trigger a name (top left) and click **Save** (top right).
10. Save your tag (top right).

### Web Tag Setup
#### Import the Web Google Tag Manager Config Variable Template
1. Once looking at the web container within Tag Manager select **Templates** in the left menu.
2. On the templates page next to **Variable Templates** select **New**.
3. From here select the **three vertical dots menu** next to save and select **Import**.
4. Select the **Web Config Variable template** (web_config_variable.tpl file as mentioned above) and once loaded select **Save** in the upper right corner.

#### Create & Configure the Variable That Will Use This Template
1. Once looking at the web container within Tag Manager select **Variables** in the left menu.
2. On the variables page next to **User-Defined Variables** select **New**.
3. Change the name in the top left to something more identifiable for the purpose such as **reCAPTCHA Config**.
4. Select anywhere in the **Variable Configuration** box.
5. In the menu that appears select **reCAPTCHA Configuration**.
6. Select the appropriate **Version** of reCAPTCHA (v3 or Enterprise).
7. Enter the necessary configuration settings for the version selected (see above **reCAPTCHA Setup** for details on how to acquire these).
8. Select **Save** in the upper right corner.

#### Import the Web Google Tag Manager Tag Template
1. Once looking at the web container within Tag Manager select **Templates** in the left menu.
2. On the templates page next to **Tag Templates** select **New**.
3. From here select the **three vertical dots menu** next to save and select **Import**.
4. Select the **Web Tag template** (web_tag.tpl file as mentioned above) and once loaded select **Save** in the upper right corner.

#### Create & Configure the Tags That Will Use This Template
> You'll need to create at least two separate tags using this template (one for initialization and one for assessing).
1. Once looking at the web container within Tag Manager select **Tags** in the left menu.
2. On the tags page next to **Tags** select **New**.
3. Change the name in the top left to something more identifiable for the purpose such as **reCAPTCHA Tag**.
4. Select anywhere in the **Tag Configuration** box.
5. In the menu that appears select **reCAPTCHA**.
6. In the **Config** box select the **[ + ]** and select **reCAPTCHA Config**.

##### Initialization Tag
> Loads the reCAPTCHA library.
7. In the **Behavior** box select **Initialize**.
8. Add an **Initialization - All Pages** trigger.

##### Gather Data Tag
> Calls reCAPTCHA execute with an action name. You should add one or more of these strategically for meaningful user interactions with your site. This will helps reCAPTCHA better identify bad actors.
7. In the **Behavior** box select **Gather Data**.
8. In the **Action** box type in a human readable name that describes the meaningful user interaction.
9. Add **Trigger(s)** that encapsulate the user behavior associated with the action.
    * **Notice:** Avoid adding an Page Load trigger such as "All Pages" as the data available at this point in the user journey is limited and not useful.

##### Assess Tag
> Calls reCAPTCHA execute with an action name, then attaches the resulting token along with other data to the data layer under a variable called "recaptcha". These tags should be associated with the user interaction that you ultimately want to score in real-time.
7. In the **Behavior** box select **Assess**.
8. In the **Action** box type in a human readable name that describes the meaningful user interaction.
9. Save this tag.
10. Edit your existing GA4 Event tag.
    > This event will act as the delivery mechanism for the reCAPTCHA token and other related data so that sGTM can send it to reCAPTCHA Enterprise API to create an assessment which has a score.

    > **Notice:** If you're using a Form Submission trigger for this GA4 Event tag and the form submission would generally cause it to advance to another page or refresh you'll want to have it configured to **Wait for Tags** (so, this should be checked and should be given at least a second - that being 1000 milliseconds).
    * Under **Event Parameters** on this GA4 event tag add a row where the **Parameter Name** is **recaptcha** and the value points to the **Data Layer Variable** also named **recaptcha**.
        * Click the plus block next to the value input box.
        * Click the plus at the top right corner.
        * Click the **Varaible Configuration** box.
        * Click **Data Layer Variable** under **Page Variables**.
        * In **Data Layer Variable Name** type **recaptcha**.
        * Give the variable a name (top left) and click **Save** (top right).
    * Under **Advanced Settings** > **Tag Sequencing** check **Fire a tag before ... fires** and select your reCAPTCHA Assess Behavior Tag as the **Setup Tag**.
    * Save your tag configuration.
