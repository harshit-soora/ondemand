'use strict';

/*
 * Workflow advanced overrides — dropdown filter & repeatable fields.
 *
 * launcher_edit.js drives the "Add new option" dropdown from its own
 * newFieldData object, which lists every launcher field. On the workflow
 * page we only want to expose six of them, so we filter the dropdown
 * after launcher_edit.js has populated it. The same hook also re-evaluates
 * the Add/No-more-options button label based on the filtered list.
 *
 * auto_environment_variable is a special case: a launcher can carry
 * arbitrarily many env vars (each one's id gets the variable name
 * appended once the user types into the name field). To support adding
 * multiple env vars on the workflow page too, we treat env var as
 * always-available — never filtered out of the dropdown, never used to
 * decide that "no more options" remain.
 */

const ALLOWED = [
  'auto_accounts',
  'auto_environment_variable',
  'auto_queues',
  'auto_batch_clusters',
  'bc_num_hours',
  'auto_job_name'
];

// Fields that may be added repeatedly. Their dropdown entry is never
// filtered out, and they don't count toward the "no more options"
// check — so the Add button stays enabled even after one is on the page.
const REPEATABLE = ['auto_environment_variable'];

// Mirrors the labels in launcher_edit.js's newFieldData, used when we
// need to re-insert a repeatable option that launcher_edit.js skipped.
const REPEATABLE_LABELS = {
  auto_environment_variable: 'Environment Variable'
};

function filterDropdown(selectEl) {
  Array.from(selectEl.options).forEach((opt) => {
    if (ALLOWED.indexOf(opt.value) === -1) {
      opt.remove();
    }
  });

  // launcher_edit.js's updateNewFieldOptions skips a field if
  // #launcher_<id> already exists. For repeatable fields we want
  // them to keep showing up, so re-add any that got skipped.
  REPEATABLE.forEach((id) => {
    if (ALLOWED.indexOf(id) === -1) return;
    const present = Array.from(selectEl.options).some((opt) => opt.value === id);
    if (!present) {
      const opt = document.createElement('option');
      opt.value = id;
      opt.text = REPEATABLE_LABELS[id] || id;
      selectEl.add(opt);
    }
  });
}

function refreshAddButtonLabel() {
  const btn = document.getElementById('add_new_field_button');
  if (!btn) return;

  // Repeatable fields always count as "still addable". For the rest,
  // an option remains as long as #launcher_<id> isn't on the page yet.
  const remaining = ALLOWED.some((id) => {
    if (REPEATABLE.indexOf(id) !== -1) return true;
    return document.getElementById('launcher_' + id) === null;
  });
  btn.textContent = remaining ? 'Add new option' : 'No more options';
  btn.disabled = !remaining;
}

// launcher_edit.js wires its remove/edit click handlers like:
//   $('.new_launcher').find('.editable-form-field').find('.btn-danger')...
// The workflow form has no `.new_launcher` ancestor, so server-rendered
// fields (the ones loaded from saved advanced_overrides on edit) never
// get those handlers — meaning their Remove button does nothing.
// Newly-added fields are unaffected because addInProgressField attaches
// handlers inline as it inserts each field.
//
// We re-bind here, scoped to the advanced overrides card, so existing
// fields behave the same as freshly-added ones.
function wireExistingFieldHandlers() {
  const card = document.getElementById('workflow_advanced_card');
  if (!card) return;

  // Remove (trash) buttons: drop the field from the DOM, then refresh
  // the Add-button label. Removed fields aren't submitted, so the
  // controller's extract_advanced_overrides will leave them out of the
  // saved hash on the next save.
  card.querySelectorAll('.editable-form-field .btn-danger').forEach((btn) => {
    btn.addEventListener('click', (event) => {
      const entireDiv = event.target.parentElement;
      entireDiv.remove();
      refreshAddButtonLabel();
    });
  });

  // Edit (pencil) buttons toggle the edit panel open, mirroring
  // launcher_edit.js's showEditField/saveEdit pair.
  card.querySelectorAll('.editable-form-field .btn-primary').forEach((editBtn) => {
    editBtn.addEventListener('click', (event) => {
      const entireDiv = event.target.parentElement;
      const editField = entireDiv.querySelector('.edit-group');
      if (editField) editField.classList.remove('d-none');

      const saveButton = entireDiv.querySelector('.btn-success');
      if (saveButton) saveButton.classList.remove('d-none');
      event.target.disabled = true;

      if (saveButton) {
        saveButton.onclick = (e) => {
          const div = e.target.parentElement;
          const ef = div.querySelector('.edit-group');
          if (ef) ef.classList.add('d-none');
          const sb = div.querySelector('.btn-success');
          const eb = div.querySelector('.btn-primary');
          if (sb) sb.classList.add('d-none');
          if (eb) eb.disabled = false;
        };
      }
    });
  });
}

document.addEventListener('DOMContentLoaded', () => {
  const btn = document.getElementById('add_new_field_button');
  if (!btn) return;

  // launcher_edit.js attaches a click handler that builds the <select>.
  // We wait one tick after that click fires so the options exist, then
  // trim the ones we don't want.
  btn.addEventListener('click', () => {
    setTimeout(() => {
      const sel = document.getElementById('add_new_field_select');
      if (sel) filterDropdown(sel);
    }, 0);
  });

  // Wire remove/edit handlers on server-rendered fields (saved overrides
  // loaded on the edit page). Newly-added fields handle this themselves.
  wireExistingFieldHandlers();

  // Also correct the button label on initial load: launcher_edit.js
  // checks against its full newFieldData, but our allowed list is shorter.
  refreshAddButtonLabel();

  // And recompute the label when an in-progress field is committed
  // or removed. The simplest signal is a click anywhere inside the
  // advanced card; the button text is cheap to recompute.
  const card = document.getElementById('workflow_advanced_card');
  if (card) {
    card.addEventListener('click', () => {
      setTimeout(refreshAddButtonLabel, 0);
    });
  }
});