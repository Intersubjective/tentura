module.exports = {
  client: {
    service: {
      name: 'tentura',
      localSchemaFile: 'lib/data/gql/schema.graphql',
    },
    includes: ['./lib/**/*.graphql'],
    excludes: ['./lib/data/gql/schema.graphql'],
  },
};
