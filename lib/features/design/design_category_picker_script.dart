import 'dart:convert';

import '../../core/cloud_api/cloud_energy_categories.dart';

String buildDesignCategoryPickerScript(EnergyCategories categories) {
  final groups = jsonEncode(
    categories.groups
        .map(
          (group) => {
            'key': group.key,
            'label': group.label,
            'types': group.types
                .map((type) => {'key': type.key, 'label': type.label})
                .toList(),
          },
        )
        .toList(),
  );
  return '''
    (() => {
      const groups = $groups;
      const category = document.getElementById('energy-category');
      const type = document.getElementById('energy-type');
      if (!category || !type) return false;
      const option = (value, label) => new Option(label, value);
      const selectGroup = () => {
        type.replaceChildren(option('', category.value ? 'Choose type' : 'Choose category first'));
        const group = groups.find((item) => item.key === category.value);
        for (const item of group?.types || []) type.add(option(item.key, item.label));
        type.disabled = !group;
      };
      category.replaceChildren(option('', 'Choose category'));
      for (const group of groups) category.add(option(group.key, group.label));
      category.addEventListener('change', selectGroup);
      window.energyLensSelectType = (key) => {
        const group = groups.find((item) => item.types.some((type) => type.key === key));
        if (!group) return;
        category.value = group.key;
        selectGroup();
        type.value = key;
      };
      selectGroup();
      return true;
    })()
  ''';
}
