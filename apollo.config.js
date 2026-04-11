module.exports = {
  client: {
    service: {
      name: 'tentura',
      localSchemaFile: './packages/client/lib/data/gql/schema.graphql',
    },
    includes: ['./packages/client/lib/**/*.graphql'],
    excludes: ['./packages/client/lib/data/gql/schema.graphql'],
  },
};
