export interface ILLMUsage {
  input_tokens: number;
  output_tokens: number;
}

export interface ILLMResult {
  text: string;
  usage: ILLMUsage;
}
