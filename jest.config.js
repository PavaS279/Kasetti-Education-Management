const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  moduleNameMapper: {
    ...(jestConfig.moduleNameMapper || {}),
    "^c/kemStyles$": "<rootDir>/jest-mocks/cssModule.js",
    "^lightning/modal$": "<rootDir>/jest-mocks/lightningModal.js"
  },
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver"]
};
