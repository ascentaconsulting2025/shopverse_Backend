export const apiSuccess = (data: any) => ({ success: true, data });
export const apiFail = (message: string, code?: string) => ({ success: false, error: { code, message } });
