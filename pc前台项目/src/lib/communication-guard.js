// A device call reserves the shared microphone before its server request starts.
// Legacy person/SOS entry points must not replace that pending or active session.
export function createCommunicationGuard() {
  let owner = null;
  function assertAvailable(token) {
    if (owner && owner !== token) throw Error('请先结束调度通信中的通话，并等待服务器确认');
  }
  return {
    assertAvailable,
    acquire() { assertAvailable(); owner = Symbol('device-call'); return owner; },
    release(token) { if (owner === token) owner = null; },
  };
}
export const communicationGuard = createCommunicationGuard();
