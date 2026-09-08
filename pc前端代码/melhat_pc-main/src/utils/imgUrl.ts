// @ts-ignore
const baseUrl = import.meta.env.VITE_APP_BASE_API;

export const getImgUrl = (url: string) => {
  return baseUrl + url;
};

export const getImgListUrl = (arr: string[]) => {
  return arr.map(getImgUrl);
};
