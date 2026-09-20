import * as provider from '@vitals-provider'
import { validateVitals } from '@/utils/vitals-contract'
export const simulatedVitals = provider.simulated
export async function getVitals(params, signal) {
  const response = await provider.read(params, signal)
  validateVitals(response.data, params)
  return response
}
