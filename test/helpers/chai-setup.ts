import { expect } from "chai";
import "@nomicfoundation/hardhat-chai-matchers";

export const expectEqual = (actual: any, expected: any) => {
  if (typeof actual === 'bigint' && typeof expected === 'number') {
    expect(Number(actual)).to.equal(expected);
  } else if (typeof actual === 'bigint' && typeof expected === 'bigint') {
    expect(actual).to.equal(expected);
  } else {
    expect(actual).to.equal(expected);
  }
};

export { expect };