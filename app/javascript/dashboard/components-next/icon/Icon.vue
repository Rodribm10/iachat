<script setup>
import { h, isVNode } from 'vue';

const props = defineProps({
  icon: { type: [String, Object, Function], required: true },
});

const renderIcon = () => {
  if (!props.icon) return null;
  if (isVNode(props.icon)) {
    return props.icon;
  }
  if (typeof props.icon === 'function') {
    const resolved = props.icon();
    return isVNode(resolved) ? resolved : h(props.icon);
  }
  return h('span', { class: props.icon });
};
</script>

<template>
  <component :is="renderIcon" />
</template>
