const findDeptNode = (nodeArr, deptId) => {
  if (!nodeArr || nodeArr.length === 0) {
    return null;
  }

  for (let index = 0; index < nodeArr.length; index++) {
    const e = nodeArr[index];

    if (e.id == deptId) {
      return e;
    }

    if (e.children && e.children.length > 0) {
      const result = findDeptNode(e.children, deptId);
      if (result != null) {
        return result;
      }
    }
  }

  return null;
};

export const findDeptNodeName = (nodeArr, deptId) => {
  const node = findDeptNode(nodeArr, deptId);
  if (node) {
    return node.label;
  }
  return "";
};

export default findDeptNode;
