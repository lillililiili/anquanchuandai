import { describe, it, expect } from 'vitest'
import { createBusinessConfigApi } from './businessConfigApi'
describe('shared simulated watch configuration',()=>{
  it('saves the versioned visibility setting and refreshes authoritative state',async()=>{
    const requests=[]; const api=createBusinessConfigApi({token:()=> 'test-token',fetchImpl:async(url,options)=>{requests.push({url,options});return{ok:true,json:async()=>({simulatedWatchVisible:false,version:2})}}})
    await api.read(); const result=await api.save(false,1); await api.state()
    expect(result.simulatedWatchVisible).toBe(false)
    expect(requests.map(r=>r.url)).toEqual(['/api/admin/v1/business-config','/api/admin/v1/business-config','/api/admin/v1/state'])
    expect(JSON.parse(requests[1].options.body)).toEqual({simulatedWatchVisible:false,expectedVersion:1})
    expect(requests[1].options.method).toBe('PATCH')
  })
  it('propagates permission and version failures instead of showing a saved setting',async()=>{
    for(const status of [403,409]) {
      const api=createBusinessConfigApi({token:()=>'',fetchImpl:async()=>({ok:false,status,json:async()=>({message:'无法保存'})})})
      await expect(api.save(false,1)).rejects.toMatchObject({code:status,message:'无法保存'})
    }
  })
  it('discards a response after the login identity changes',async()=>{
    let token='first'; const api=createBusinessConfigApi({token:()=>token,fetchImpl:async()=>({ok:true,json:async()=>{token='second';return {simulatedWatchVisible:false}}})})
    await expect(api.save(false,1)).rejects.toMatchObject({name:'AbortError'})
  })
})
