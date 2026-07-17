import * as msal from "@azure/msal-node";
import fs from "fs";
import { SecretClient } from "@azure/keyvault-secrets";
import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

class MyClientAssertionCredential {
    constructor() {
        let clientAssertion = "";
        try {
            clientAssertion = fs.readFileSync(process.env.AZURE_FEDERATED_TOKEN_FILE, 'utf-8');
        } catch (err) {
            throw Error("Failed to read client assertion file: " + err);
        }

        this.app = new msal.ConfidentialClientApplication({
            auth: {
                clientId: process.env.AZURE_CLIENT_ID,
                authority: `${process.env.AZURE_AUTHORITY_HOST}${process.env.AZURE_TENANT_ID}`,
                clientAssertion: clientAssertion,
            }
        });
    }

    async getToken(scopes=['https://vault.azure.net/.default']) {
        const token = await this.app.acquireTokenByClientCredential({ scopes });
        
        return {
          token: token.accessToken,
          expiresOnTimestamp: token.expiresOn.getTime(),
        };
    }
}

const app = express();
const port = 8080;

// Vulnerable Endpoint 1: Accessing Environment Variables (Simulation)
app.get('/env', (req, res) => {
  const envVar = req.query.name;
  const value = process.env[envVar]; 
  res.send(value);
});

// Vulnerable Endpoint 2: Path Traversal (Simulation)
app.get('/file', (req, res) => {
  const file = req.query.name;
  const value = fs.readFileSync(path.join(__dirname, file));
  res.send(value);
});

app.listen(port, () => {
  console.log(`Server listening on port ${port}`);
});

const main = async () => {
    // create a token credential object, which has a getToken method that returns a token
    const tokenCredential = new MyClientAssertionCredential();

    const keyvaultURL = process.env.KEYVAULT_URL;
    if (!keyvaultURL) {
        throw new Error("KEYVAULT_URL environment variable not set");
    }
    const secretName = process.env.SECRET_NAME;
    if (!secretName) {
        throw new Error("SECRET_NAME environment variable not set");
    }

    // create a secret client with the token credential
    const keyvault = new SecretClient(keyvaultURL, tokenCredential);
    console.log(`successfully created secret client, keyvaultURL=${keyvaultURL}, secretName=${secretName}`);
    console.log(`getting secret, Name=${tokenCredential}`);
    const secret = await keyvault.getSecret(secretName);
    console.log(`Secret object: ${JSON.stringify(secret, null, 2)}`);
    if (secret) {
      console.log(`Successfully got secret, secret value=${secret.value}`);
    } else {
      console.log('Failed to get secret, secret object is null or undefined');
    }
}

main().catch(console.error);