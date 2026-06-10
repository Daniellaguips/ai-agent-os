The user is reporting bugs they found that the debug team missed. This is how the system improves.

## Process

1. **Read the user's bug report** from the argument: $ARGUMENTS

2. **For each bug reported**:
   a. Classify the bug into a generalizable pattern (not just the specific instance)
   b. Create a check that would catch this class of bug anywhere in any codebase
   c. Fix the specific bug immediately
   d. Run the check across the entire codebase to find other instances of the same pattern

3. **Update `.claude/debug-patterns.md`**:
   - Add a new numbered pattern entry for each bug class
   - Increment the "Bugs caught by human" counter
   - Update the "Last updated" date
   - Include: date, "Found by: human", description, where found, generalizable check, fix pattern

4. **Run `/debug`** after updating patterns to verify the fix AND check if the new pattern catches anything else in the codebase.

5. **Report back** with:
   ```
   ## Bugs Fixed
   - What was wrong, where, and how it was fixed
   
   ## New Patterns Added to debug-patterns.md
   - Pattern name + what it checks for
   
   ## Other Instances Found
   - Any other places in the codebase where the same pattern appeared
   ```

## Example
User says: "the checkout crashes when the cart is empty"

You would:
1. Fix the specific bug (guard against empty array before processing)
2. Add pattern: "Array operation without empty-check on user-provided collections"
3. Search all files for array operations (map, reduce, filter, [0]) on data from API/user input without length checks
4. Fix any other instances found
5. Update debug-patterns.md
