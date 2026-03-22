// Force the linker to keep TensorFlowLiteC symbols.
// Only Dart FFI references these at runtime via dlsym(), so without a
// compile-time reference the linker dead-strips them from release builds.
// This function is never called — its mere existence creates the reference.

#import <TensorFlowLiteC/TensorFlowLiteC.h>

void _keepTfLiteSymbols(void) __attribute__((used));
void _keepTfLiteSymbols(void) {
  (void)TfLiteModelCreate;
  (void)TfLiteModelDelete;
  (void)TfLiteInterpreterCreate;
  (void)TfLiteInterpreterDelete;
  (void)TfLiteInterpreterAllocateTensors;
  (void)TfLiteInterpreterInvoke;
  (void)TfLiteInterpreterGetInputTensor;
  (void)TfLiteInterpreterGetOutputTensor;
  (void)TfLiteInterpreterGetInputTensorCount;
  (void)TfLiteInterpreterGetOutputTensorCount;
  (void)TfLiteInterpreterOptionsCreate;
  (void)TfLiteInterpreterOptionsDelete;
  (void)TfLiteInterpreterOptionsSetNumThreads;
  (void)TfLiteTensorCopyFromBuffer;
  (void)TfLiteTensorCopyToBuffer;
  (void)TfLiteTensorData;
  (void)TfLiteTensorByteSize;
  (void)TfLiteTensorName;
  (void)TfLiteTensorType;
  (void)TfLiteTensorNumDims;
  (void)TfLiteTensorDim;
  (void)TfLiteVersion;
}
