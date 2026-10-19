const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

for (const page of ['settings_manual_device_entry', 'settings_manage_devices']) {
  test(`${page} exposes the picker and toggles Room suggestions`, () => {
    const html = fs.readFileSync(`assets/design_pages/${page}/app.html`, 'utf8');
    for (const id of ['dd-category', 'dd-type', 'menu-category', 'menu-type',
      'energy-category', 'energy-type', 'input-room', 'room-suggestions']) {
      assert.equal((html.match(new RegExp(`id="${id}"`, 'g')) || []).length, 1, id);
    }
    assert.match(html, /id="dd-category"[^>]*role="combobox"[^>]*aria-haspopup="listbox"/);
    assert.match(html, /id="dd-type"[^>]*role="combobox"[^>]*aria-disabled="true"/);
    assert.match(html, /id="room-suggestions"/);
    assert.match(html, /aria-label="Room suggestions"/);
    assert.equal((html.match(/class="el-room-chip"/g) || []).length, 6);
    for (const id of ['input-device-name', 'input-manufacturer', 'input-model']) {
      assert.match(html, new RegExp(`<input class="[^"]*min-h-12[^"]*" id="${id}"`));
    }

    const script = html.match(/<script>\s*\(\(\) => \{\s*const room = document\.getElementById\('input-room'\);([\s\S]*?)<\/script>/)?.[0]
      .replace(/^<script>/, '').replace(/<\/script>$/, '');
    assert.ok(script, 'Room behavior script');
    const labels = ['Kitchen', 'Living room', 'Bedroom', 'Office', 'Garage', 'Laundry'];
    const room = {
      value: '', listeners: {},
      addEventListener(name, fn) { this.listeners[name] = fn; },
      dispatchEvent(event) { this.listeners[event.type]?.(); },
      focus() { this.focused = true; },
    };
    const chips = labels.map((textContent) => ({
      textContent, attrs: {}, listeners: {},
      setAttribute(name, value) { this.attrs[name] = value; },
      getAttribute(name) { return this.attrs[name]; },
      addEventListener(name, fn) { this.listeners[name] = fn; },
    }));
    vm.runInNewContext(script, {
      document: {
        getElementById(id) { return id === 'input-room' ? room : null; },
        querySelectorAll() { return chips; },
      },
      Event: class { constructor(type) { this.type = type; } },
    });
    chips[1].listeners.click();
    assert.equal(room.value, 'Living room');
    assert.equal(chips[1].attrs['aria-pressed'], 'true');
    chips[1].listeners.click();
    assert.equal(room.value, '');
    room.value = 'office';
    room.dispatchEvent({type: 'input'});
    assert.equal(chips[3].attrs['aria-pressed'], 'true');
    room.value = 'Custom room';
    room.dispatchEvent({type: 'input'});
    assert.equal(chips.some((chip) => chip.attrs['aria-pressed'] === 'true'), false);
  });
}
