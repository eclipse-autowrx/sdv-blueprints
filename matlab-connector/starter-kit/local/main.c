#include "da_connector.h"
#include <stdio.h>

int main(int argc, char *argv[])
{
  printf("Starting DA Connector...\n");

  double result = da_connector();
  printf("da_connector() returned: %.2f\n", result);

  return 0;
}
