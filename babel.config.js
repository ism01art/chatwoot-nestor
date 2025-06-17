/* eslint-disable global-require */
module.exports = api => {
  const validEnv = ['development', 'test', 'production'];
  const currentEnv = api.env();

  if (!validEnv.includes(currentEnv)) {
    throw new Error(
      `Please specify a valid NODE_ENV or BABEL_ENV environment variable. Valid values are "development", "test", and "production". Received: ${JSON.stringify(currentEnv)}.`
    );
  }

  return {
    presets: [
      [
        require('@babel/preset-env').default,
        {
          useBuiltIns: 'usage',
          corejs: 3,
          targets: {
            browserslist: '> 0.25%',
          },
        },
      ],
    ],
    plugins: [
      'babel-plugin-macros',
      '@babel/plugin-proposal-nullish-coalescing-operator',
      [
        '@babel/plugin-proposal-class-properties',
        {
          loose: true,
        },
      ],
      'babel-plugin-transform-vue-jsx',
    ],
  };
};
