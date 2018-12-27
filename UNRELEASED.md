# # Unreleased changes

## 0.10.0

- BREAKING CHANGE: `withBrowserBehavior` has been renamed to `enhanceVisitWithBrowserBehavior` and only accepts one arg, the visit action creator.
- BREAKING CHANGE: All keys `json.my_key_here` in BreezyTemplate will `key_format` to camelCase `{"myKeyHere": 'foobar'}`. This makes working with props received via `mapStateToProps` easier to work with.
- FIX: `remote` now merges joints on graft requests
- BREAKING CHANGE: `remote` will update all joints before fetching nodes when using deferment. The previous behavior was to update after all deferred fetches were finished, but this caused some issues and confusion around proper behavior. This will be the fix for now.
- NEW: Breezy now dispatches `@@breezy/GRAFTING_ERROR`. This is a listenable action that you can use to retry deferments that fail due to network errors. You will recieve the `pageKey`, the `url` that failed, and the `keyPath` to the missing node.
- `remote` now has a fallback `pageKey` if one isn't provided.
- `ensureSingleVisit`, the function that powers `visit` is now exposed for use. Come in super handy when you want to create your own `visit` function. For example, instaclick functionality.

- Remove immutable helpers. It doesn't seem like good practice to create immutable action creators, probably doing too much work for the user and makes testing more difficult. Instead recommend and document immmer usage and keep getIn (exported for traversing), and setIn (for internal use) around.

- Added a kitchen sink app in the example dir that demos everything
