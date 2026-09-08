import { reactive, UnwrapNestedRefs } from 'vue'

type OutputType<O extends object, T extends object> = O & {
  bindProps: UnwrapNestedRefs<T>
}

export function hookResult<H extends object, P extends object>(
  handler: H,
  bindProps: P
): OutputType<H, P> {
  return {
    ...handler,
    bindProps: reactive(bindProps)
  }
}
