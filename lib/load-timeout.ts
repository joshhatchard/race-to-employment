export async function withLoadTimeout<T>(work: PromiseLike<T>, stage: string, milliseconds = 12000): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      Promise.resolve(work),
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error(stage)), milliseconds);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}
