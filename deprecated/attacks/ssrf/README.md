# SSRF Demo Application

This is a simple demo application that demonstrates how to exploit a Server-Side Request Forgery (SSRF) vulnerability to retrieve an IAM service account access token from the Google Cloud Metadata API, with which a secret can be accessed from Google Cloud Secret Manager.


## Setup

First, we have to create a `.env` file based on the provided `.env.example` file. To do so, copy the `.env.example` file to a new `.env` file:

```bash
cp .env.example .env
```

Next, replace the placeholder values in the `.env` file with your own values and source the file to set the environment variables:

```bash
export $(cat .env | xargs)
```

After that, we can create the Kubernetes service account and deploy the vulnerable application:

```bash
envsubst < deploy.yaml | kubectl apply -f -
```

Once the application is deployed, we can create the Google Cloud Secret Manager secret and the IAM service account with the necessary permissions to access the secret using terraform:

```bash
cd terraform
terraform init
terraform apply
cd ..
```

Now everything is set up so we can start exploiting the SSRF vulnerability.


## Token Theft

We can make use of the vulnerable application either by navigating the website in the browser or by using our provided shell script.

### Web Interface

To access the web interface we can access the application using the domain specified in the `USER_SERVICE_DOMAIN` environment variable or by port-forwarding the service to our local machine:

```bash
kubectl port-forward -n users service/user-service 8080:80
```

Once we have opened the web interface, we can log into the account using the following credentials:

- Username: `foo`
- Password: `bar`

After logging in, we are presented with the users profile page. By clicking on the profile picture, we are provided with a prompt to either select a new profile image locally or by providing a URL pointing to an image. Here we can enter the URL pointing to the metadata API to retrieve the access token: [http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token](http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token)

When we now click on the `Upload` button, the user's profile picture is updated, but cannot be properly displayed as the image data is now set to the response of the access token request. To retrieve the access token, we can take a look at the image source opening the developer console and executing the following JavaScript code:

```javascript
const imageSrc = document.getElementById('profile-picture').src; imageSrc
``` 

We can see, that the image source is set to a data URL containing some base64 encoded data. We can use the following code to decode the base64 data:

```javascript
response = atob(imageSrc.split(',')[1]); response
```

The result is a JSON object containing the access token. To extract the token execute:

```javascript
JSON.parse(response)['access_token']
```

### Shell Script

With the [steal-token.sh](scripts/steal-token.sh) script, we can extract the access token by sending HTTP requests to the user service. To use the script, provide the URL of the user service as an argument:

```bash
scripts/steal-token.sh <user-service-url>
```

For example, if you have port-forwarded the user service to your local machine, you can use the following command:

```bash
scripts/steal-token.sh http://localhost:8080
```


## Secret Access

With the access token, we can now access the secret stored in Google Cloud Secret Manager. To do so, we can use the [access-secret.sh](scripts/access-secret.sh) script. The script requires the access token as an argument:

```bash
scripts/access-secret.sh <access-token>
```

The result is the value of the secret stored in Google Cloud Secret Manager.