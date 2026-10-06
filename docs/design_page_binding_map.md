# Design page identification markers

`design_page_binding_map.json` is an internal path-to-ID manifest for the 14
packaged pages. `tool/mark_design_bindings.py` reproduces the markers from the
frozen golden fixtures. It edits `app.html` only. Each `data-el-bind` identifies
a text-bearing element, `data-el-field` identifies a form input, and
`data-el-action` identifies a control. IDs are page-local and stable for this
fixture revision. They do not activate an API, change a control's behavior, or
authorize replacing the approved text. Some markers contain nested text nodes;
the later renderer must resolve those before using `textContent`.

All non-icon text paths and all anchors, buttons, inputs, selects, and textareas
in the frozen fixtures are mapped. Static labels are included so future page
composition can address them, but the backend must not treat them as live data.
The exact customer presentation for missing, loading, stale, and offline values
still requires owner approval.

The following source controls have no approved native outcome: Quick Nap,
assistant prompt, dashboard period selectors, Devices filters/sort/pagination,
Automate Cutoff, Set Reminder, Sync Thermostat, promotional links, profile
Edit/Change, candidate adoption, manual Save, photo/camera/gallery and Delete.
The existing local FAQ accordion/search and checkbox behavior remains as-is.
No entity IDs were inferred from sample labels, and no action is enabled by
these markers. Visible chart geometry, images, and CSS are still static assets;
their future data mapping depends on approved contracts and presentation.
