export function failure(code, message, errorCode = 'MOCK_' + code) { return Object.assign(new Error(message), { code, errorCode }) }
