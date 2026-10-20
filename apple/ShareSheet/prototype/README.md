# Share-sheet corrections prototype

Throwaway design exploration for [Shape inline recipe corrections in the share sheet](https://github.com/xchrisbailey/cauldron.srcery/issues/215). This branch is evidence for a decision; do not merge it into the app.

Open `share-sheet-corrections-preview.html` in a browser. It is self-contained and needs no server or dependencies. The adjacent `share-sheet-corrections.html` is the editable fragment used in the conversation.

Compare three structurally different interactions using the bottom carousel:

- **Visible fields**: all four fields are immediately editable. Recommended for discoverability and missing information.
- **Tap to correct**: compact summary rows reveal one field on demand.
- **Details drawer**: the recipe summary precedes a collapsible four-field form.

The platform selector switches the action label and the 380×520 Mac popover versus the taller iPhone sheet. The recipe selector supplies a missing-title or complete example. Edit values, try saving invalid servings, leave optional numbers blank, or continue with an incomplete draft. The same field values are reflected across designs.

Proposed validation: a title is required, with the existing 200-character limit; optional servings are whole numbers from 1 to 1000; optional times are whole minutes from 0 to 20160. Blank numeric values stay unspecified, not zero. Missing title is flagged initially; other validation appears after leaving a field or attempting Save. Save remains visible and focuses the first invalid field. Continuation accepts incomplete drafts for repair. No actual recipe or draft is persisted by the demo; all button outcomes are simulated.

Enter advances through the visible form or closes the current tap-to-correct field. Native controls have visible labels and error associations. The footer remains available while content scrolls, including in the fixed Mac size. Browser keyboard and layout behavior are only approximations of SwiftUI: iPhone keyboard avoidance, Dynamic Type, VoiceOver, signed extension launch and real persistence still require implementation checks.

Manual browser checks: entered a missing title and observed simulated successful Save; entered zero servings and observed correction state; used continuation with an invalid field; switched platform and confirmed Mac labeling; switched to tap-to-correct and revealed its title field. These checks do not validate the production app.

The [handoff decision](https://github.com/xchrisbailey/cauldron.srcery/issues/214#issuecomment-6283683573) is already agreed. This prototype decision stays open until Chris gives feedback; no design has been selected yet.
