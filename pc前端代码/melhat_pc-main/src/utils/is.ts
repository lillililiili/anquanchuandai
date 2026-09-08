export function isArray(arr: any): arr is Array<any> {
  return Object.prototype.toString.call(arr) === '[object Array]'
}
