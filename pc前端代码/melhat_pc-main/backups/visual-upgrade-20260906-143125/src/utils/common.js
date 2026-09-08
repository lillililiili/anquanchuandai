/**
 * 递归查找部门名称
 * @param {Array} depts 部门树数据
 * @param {string} deptId 部门ID
 * @returns {string} 部门名称
 */
export function findDeptName(depts, deptId) {
    for (const dept of depts) {
      if (dept.id === deptId) {
        return dept.label;
      }
      if (dept.children && dept.children.length > 0) {
        const name = findDeptName(dept.children, deptId);
        if (name) return name;
      }
    }
    return "";
  }