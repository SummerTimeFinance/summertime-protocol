const fs = require('fs');
const yaml = require('js-yaml');
const uuidv4 = require('uuid/v4');

const defaultEnvVariables = ['SESSION_SECRET_KEY', 'WEB_TOKEN_SECRET'];
const requiredEnvVariables = [
	'ENDPOINT',
	'CONTRACT_ABI',
	'CONTRACT_BYTECODE',
	'ETHEREUM_ADDRESS',
];

// if an env has not been provided, default to development
if (!('NODE_ENV' in process.env)) process.env.NODE_ENV = 'development';

let appYamlConfigFile = 'app.yaml';
if (process.env.NODE_ENV === 'production') {
  appYamlConfigFile = 'app.prod.yaml';
}

if (process.env.NODE_ENV === 'staging') {
  appYamlConfigFile = 'app.staging.yaml';
}

// default configuration
process.env.API_VERSION = 1;
defaultEnvVariables.forEach((configVar) => {
  process.env[configVar] = uuidv4();
});

// If MIGRATION is true in ENV, it will ignore NODE_ENV === development
// This allows us to run migration scripts
if (process.env.NODE_ENV === 'development' || process.env.MIGRATIONS) {
  const envKeys = Object.keys(process.env);
  const allRequiredEnvVariablesExist = requiredEnvVariables.every(
    (variable) => envKeys.indexOf(variable) !== -1
  );

  // if the requiredEnvVariables have not been added from your server backend (heroku, GAE etc.)
  if (!allRequiredEnvVariablesExist) {
    if (fs.existsSync(appYamlConfigFile)) {
      // Get the rest of the config from app.yaml config file
      const appEnvConfigurations = yaml.safeLoad(fs.readFileSync(appYamlConfigFile, 'utf8'));
      Object.keys(appEnvConfigurations).forEach((key) => {
        process.env[key] =
          typeof appEnvConfigurations[key] !== 'string'
            ? JSON.stringify(appEnvConfigurations[key])
						: appEnvConfigurations[key];
				// console.log(key, process.env[key]);
			});
    } else {
      throw new Error(`
        Missing app.yaml config file used while in development mode
        It should have contents similar to the example below:
        app.yaml
        -------------------------
        DATABASE_URL: 'mongo+srv://raise:password@localhost:27017'
        SECRET_KEY: 'a8eac82d7ac1461ba0348b0cb24d3f8140d3afb9be864e56a10d7e8026eaed66'
        ENDPOINT: 'http://endpoint.com/v1/api/getSomething'
        -------------------------
      `);
    }
  }
}
