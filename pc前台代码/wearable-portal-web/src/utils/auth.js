export const TOKEN_KEY = import.meta.env.MODE === 'mock' ? 'Wearable-Portal-Mock-Token' : import.meta.env.MODE === 'demo' ? 'Wearable-Portal-Demo-Token' : 'Wearable-Portal-Token'
export const getToken = () => sessionStorage.getItem(TOKEN_KEY) || ''
export const setToken = (token) => sessionStorage.setItem(TOKEN_KEY, token)
export const removeToken = () => sessionStorage.removeItem(TOKEN_KEY)
