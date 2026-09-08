import useDictStore from '@/store/modules/dict';
import { getDicts } from '@/api/system/dict/data';

/**
 * 获取字典数据
 */
export function useDict(...args) {
  const res = ref({});
  return (() => {
    args.forEach((dictType) => {
      res.value[dictType] = [];
      const dicts = useDictStore().getDict(dictType);
      if (dicts) {
        res.value[dictType] = dicts;
      } else {
        getDicts(dictType).then((resp) => {
          res.value[dictType] = resp.data.map((p) => ({
            label: p.dictLabel,
            value: p.dictValue,
            elTagType: p.listClass,
            elTagClass: p.cssClass,
          }));
          useDictStore().setDict(dictType, res.value[dictType]);
        });
      }
    });
    return toRefs(res.value);
  })();
}

/**
 * 获取字典数据
 */
export function getSingleDict(dictType) {
  const dictData = useDictStore().getDict(dictType);

  if (dictData) {
    return Promise.resolve(dictData);
  } else {
    return getDicts(dictType).then((resp) => {
      const items = resp.data.map((p) => ({
        label: p.dictLabel,
        value: p.dictValue,
        elTagType: p.listClass,
        elTagClass: p.cssClass,
      }));
      useDictStore().setDict(dictType, items);

      return items;
    });
  }
}

/**
 * 根据字典数据源和值，匹配返回对应的 label
 * @param {*} options
 * @param {*} value
 * @returns
 */

export function getDictLabel(options, value) {
  if (!options || options.length === 0) {
    return '';
  }
  const item = options.find((option) => option.value === value);
  return item ? item.label : '';
}
