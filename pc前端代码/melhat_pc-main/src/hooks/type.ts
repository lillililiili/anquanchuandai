export type TApiFun<TData, TParams extends Array<any>> = (
  ...params: TParams
) => Promise<TData>
